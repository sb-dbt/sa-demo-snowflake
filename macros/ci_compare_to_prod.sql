{#
    on-run-end hook: after a Slim CI build on the `ci` target, diff every model
    that was built against its prod counterpart and log the results.
    Uses audit_helper.compare_all_columns when the model has a `unique` test
    (used as the primary key), otherwise a row-level compare_relations summary.
#}
{% macro ci_compare_to_prod(prod_schema='prod') %}
    {% if not execute or target.name != 'ci' %}
        {{ return('') }}
    {% endif %}

    {% for unique_id in selected_resources if unique_id.startswith('model.') %}
        {% set node = graph.nodes[unique_id] %}
        {% if node.config.materialized == 'ephemeral' %}{% continue %}{% endif %}

        {% set ci_rel = adapter.get_relation(node.database, node.schema, node.alias) %}
        {% set prod_rel = adapter.get_relation(node.database, prod_schema, node.alias) %}

        {{ log('', info=true) }}
        {{ log('===== Compare ' ~ node.name ~ ': ' ~ node.schema ~ ' vs ' ~ prod_schema ~ ' =====', info=true) }}

        {% if ci_rel is none %}
            {{ log('  skipped: not built in CI', info=true) }}
            {% continue %}
        {% elif prod_rel is none %}
            {{ log('  NEW MODEL: no prod relation to compare against', info=true) }}
            {% continue %}
        {% endif %}

        {# primary key = column of a single-column unique test on this model #}
        {% set ns = namespace(pk=none) %}
        {% for test in graph.nodes.values() if test.resource_type == 'test' %}
            {% if ns.pk is none
                  and test.test_metadata is defined and test.test_metadata
                  and test.test_metadata.name == 'unique'
                  and unique_id in test.depends_on.nodes %}
                {% set ns.pk = test.column_name or test.test_metadata.kwargs.get('column_name') %}
            {% endif %}
        {% endfor %}

        {% if ns.pk %}
            {{ log('  primary key: ' ~ ns.pk, info=true) }}
            {% set results = run_query(audit_helper.compare_all_columns(
                a_relation=prod_rel, b_relation=ci_rel, primary_key=ns.pk, summarize=true)) %}
            {{ log('  column | perfect_match | conflicting | null_in_prod | null_in_ci | missing_from_prod | missing_from_ci', info=true) }}
            {% for row in results.rows %}
                {% set r = dict(zip(results.column_names | map('lower'), row)) %}
                {% set changed = r['conflicting_values'] or r['missing_from_a'] or r['missing_from_b'] %}
                {{ log(('  * ' if changed else '    ') ~ r['column_name'] ~ ' | ' ~ r['perfect_match'] ~ ' | ' ~ r['conflicting_values']
                       ~ ' | ' ~ r['null_in_a'] ~ ' | ' ~ r['null_in_b'] ~ ' | ' ~ r['missing_from_a'] ~ ' | ' ~ r['missing_from_b'], info=true) }}
            {% endfor %}
        {% else %}
            {{ log('  no unique test found: row-level comparison', info=true) }}
            {% set results = run_query(audit_helper.compare_relations(
                a_relation=prod_rel, b_relation=ci_rel, summarize=true)) %}
            {% for row in results.rows %}
                {% set r = dict(zip(results.column_names | map('lower'), row)) %}
                {{ log('  in_prod=' ~ r['in_a'] ~ ' in_ci=' ~ r['in_b'] ~ ' rows=' ~ r['count'] ~ ' (' ~ r['percent_of_total'] ~ '%)', info=true) }}
            {% endfor %}
        {% endif %}
    {% endfor %}
{% endmacro %}
