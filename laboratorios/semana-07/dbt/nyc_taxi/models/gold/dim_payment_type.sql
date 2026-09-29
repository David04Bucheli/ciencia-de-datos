{#
  GOLD - Dimensión forma de pago.
  PK: payment_type_key (llave sustituta). Llave natural: payment_type_id (5 = desconocido).
#}
{{ config(materialized='table') }}

select
    {{ dbt_utils.generate_surrogate_key(['payment_type_id']) }} as payment_type_key,
    payment_type_id,
    payment_type_name,
    payment_type_description_es                                  as payment_type_description,
    payment_type_id = 1                                          as is_card_payment
from {{ ref('ref_payment_type') }}