{# Store everything as UTC timestamp_ntz: no session-timezone surprises downstream. #}
{% macro to_utc(expr) -%}
    convert_timezone('UTC', {{ expr }}::timestamp_tz)::timestamp_ntz
{%- endmacro %}

{% macro epoch_ms_to_utc(expr) -%}
    to_timestamp_ntz({{ expr }}::number, 3)
{%- endmacro %}

{% macro recon_as_of_date() -%}
    {%- set as_of = var('recon_as_of_date', none) -%}
    {%- if as_of -%} '{{ as_of }}'::date {%- else -%} current_date {%- endif -%}
{%- endmacro %}
