with 

source as (

    select * from {{ source('movie_reviews', 'raw_movie_reviews') }}

),

renamed as (

    select
        review_text,
        sentiment_value,
        id,
        movie_id,
        response_time

    from source

)

select * from renamed