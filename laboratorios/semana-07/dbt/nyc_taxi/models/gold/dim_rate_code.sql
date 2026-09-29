{#
  GOLD - Dimensión tarifa aplicada al final del viaje.
  PK: rate_code_key (llave sustituta). Llave natural: rate_code_id (99 = desconocido).
#}
{{ config(materialized='table') }}

select
    {{ dbt_utils.generate_surrogate_key(['rate_code_id']) }} as rate_code_key,
    rate_code_id,
    rate_code_name,
    rate_code_description_es                                 as rate_code_description,
    rate_code_id in (2, 3)                                   as is_airport_rate
from {{ ref('ref_rate_code') }}