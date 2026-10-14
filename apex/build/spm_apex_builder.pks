create or replace package spm_apex_builder as
    -- Hilfspaket zum Aufbau der APEX-Anwendung (nur während apex/build/spm_app_build.sql).
    -- Kapselt wwv_flow_imp_page/_shared mit den Vorgaben des Universal Theme (24.2).
    -- Aufrufe gelten jeweils für die zuletzt angelegte Seite bzw. Region.

    procedure init(p_id_base number);

    procedure page(p_id number, p_name varchar2, p_alias varchar2, p_title varchar2 default null,
                   p_public boolean default false, p_protection varchar2 default 'C',
                   p_required_role number default null, p_help clob default null);

    -- Region mit HTML aus einer PL/SQL-Funktion (Dynamic Content)
    function region_html(p_name varchar2, p_seq number, p_function_body varchar2,
                         p_items_to_submit varchar2 default null, p_hide_title boolean default false) return number;

    -- Region mit statischem HTML
    function region_static(p_name varchar2, p_seq number, p_html varchar2) return number;

    -- Leere Region für Formularfelder und Buttons
    function region_form(p_name varchar2, p_seq number) return number;

    -- Interactive Report; Spalten mit ir_col, abschließen mit ir_end
    function ir(p_name varchar2, p_seq number, p_sql varchar2, p_static_id varchar2,
                p_items_to_submit varchar2 default null, p_rows number default 15) return number;
    procedure ir_col(p_column varchar2, p_label varchar2, p_type varchar2 default 'STRING',
                     p_link varchar2 default null, p_link_text varchar2 default null,
                     p_format varchar2 default null, p_hidden boolean default false,
                     p_align varchar2 default null, p_html varchar2 default null);
    procedure ir_end(p_sort_column varchar2 default null, p_sort_desc boolean default false);

    -- p_type: TEXT, NUMBER, SELECT, TEXTAREA, HIDDEN, DISPLAY
    procedure item(p_name varchar2, p_region number, p_seq number, p_label varchar2 default null,
                   p_type varchar2 default 'TEXT', p_lov varchar2 default null, p_required boolean default false,
                   p_help varchar2 default null, p_readonly_when varchar2 default null,
                   p_new_row boolean default true, p_span number default null, p_null_text varchar2 default null);

    -- p_action: SUBMIT oder REDIRECT_URL
    function button(p_name varchar2, p_label varchar2, p_region number, p_seq number,
                    p_hot boolean default false, p_action varchar2 default 'SUBMIT',
                    p_url varchar2 default null, p_confirm varchar2 default null,
                    p_position varchar2 default 'NEXT', p_icon varchar2 default null) return number;

    -- p_point: AFTER_SUBMIT oder BEFORE_HEADER
    procedure process(p_name varchar2, p_seq number, p_code varchar2, p_point varchar2 default 'AFTER_SUBMIT',
                      p_button number default null, p_success varchar2 default null,
                      p_condition_plsql varchar2 default null);

    procedure branch(p_seq number, p_page number, p_button number default null, p_items varchar2 default null);

    procedure nav(p_list_id number, p_seq number, p_label varchar2, p_page number, p_icon varchar2,
                  p_current_pages varchar2 default null);

    -- Eintrag in der Navigationsleiste (oben rechts); p_css_class an der Listenzeile
    procedure navbar(p_list_id number, p_seq number, p_label varchar2, p_page number, p_icon varchar2,
                     p_css_class varchar2 default null);

end spm_apex_builder;
/
