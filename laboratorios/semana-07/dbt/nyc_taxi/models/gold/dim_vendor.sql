{#
  GOLD - Dimensión proveedor tecnológico (TPEP) que reportó el viaje.
  PK: vendor_key (llave sustituta). Llave natural: vendor_id (-1 = desconocido).
#}
{{ config(materialized='table') }}

select
    {{ dbt_utils.generate_surrogate_key(['vendor_id']) }} as vendor_key,
    vendor_id,
    vendor_name
from {{ ref('ref_vendor') }}