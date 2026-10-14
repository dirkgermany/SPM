create or replace package body spm_apex_builder as

    -- Universal Theme 24.2 (Template-IDs aus dem Export der Anwendung)
    C_TPL_REGION   constant number := 4072358936313175081;  -- Standard
    C_TPL_IR       constant number := 2100526641005906379;  -- Interactive Report
    C_TPL_BUTTON   constant number := 4072362960822175091;  -- Text
    C_TPL_BUTTON_I constant number := 4072362960822175091;
    C_TPL_LABEL    constant number := 1609121967514267634;  -- Optional
    C_TPL_LABEL_R  constant number := 1609122147107268652;  -- Required

    -- Seiten-CSS: "Startseite" in der Navigationsleiste als heller Button
    C_PAGE_CSS constant varchar2(1000) :=
           '.spm-home .t-Button--navBar { background: #ffffff; border-radius: 4px; margin: 0 8px; padding: 4px 12px; }' || chr(10)
        || '.spm-home .t-Button--navBar .t-Icon, .spm-home .t-Button--navBar .t-Button-label { color: #0b5cad; font-weight: bold; }' || chr(10)
        || '.spm-home .t-Button--navBar:hover { background: #e8f1fb; }';

    g_next       number;
    g_page       number;
    g_ws_cols    varchar2(4000);
    g_ws_count   pls_integer;
    g_ws_static  varchar2(100);

    function next_raw return number is
    begin
        g_next := g_next + 1;
        return g_next;
    end next_raw;

    function next_id return number is
    begin
        return wwv_flow_imp.id(next_raw);
    end next_id;

    procedure init(p_id_base number) is
    begin
        g_next := p_id_base;
    end init;

    procedure page(p_id number, p_name varchar2, p_alias varchar2, p_title varchar2 default null,
                   p_public boolean default false, p_protection varchar2 default 'C',
                   p_required_role number default null, p_help clob default null) is
    begin
        g_page := p_id;
        wwv_flow_imp_page.create_page(
            p_id                    => p_id,
            p_name                  => p_name,
            p_alias                 => p_alias,
            p_step_title            => nvl(p_title, p_name),
            p_autocomplete_on_off   => 'OFF',
            p_page_template_options => '#DEFAULT#',
            p_inline_css            => C_PAGE_CSS,
            p_protection_level      => p_protection,
            p_page_is_public_y_n    => case when p_public then 'Y' else 'N' end,
            p_required_role         => p_required_role,
            p_help_text             => p_help);
    end page;

    function region_html(p_name varchar2, p_seq number, p_function_body varchar2,
                         p_items_to_submit varchar2 default null, p_hide_title boolean default false) return number is
        l_id number := next_id;
    begin
        wwv_flow_imp_page.create_page_plug(
            p_id                       => l_id,
            p_plug_name                => p_name,
            p_region_template_options  => '#DEFAULT#' || case when p_hide_title then ':t-Region--hideHeader' end,
            p_plug_template            => C_TPL_REGION,
            p_plug_display_sequence    => p_seq,
            p_plug_source_type         => 'NATIVE_DYNAMIC_CONTENT',
            p_function_body_language   => 'PLSQL',
            p_plug_source              => p_function_body,
            p_ajax_items_to_submit     => p_items_to_submit);
        return l_id;
    end region_html;

    function region_static(p_name varchar2, p_seq number, p_html varchar2) return number is
        l_id number := next_id;
    begin
        wwv_flow_imp_page.create_page_plug(
            p_id                       => l_id,
            p_plug_name                => p_name,
            p_region_template_options  => '#DEFAULT#',
            p_escape_on_http_output    => 'Y',
            p_plug_template            => C_TPL_REGION,
            p_plug_display_sequence    => p_seq,
            p_plug_source              => p_html,
            p_attributes               => wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(
                                              'expand_shortcuts', 'N',
                                              'output_as', 'HTML')).to_clob);
        return l_id;
    end region_static;

    function region_form(p_name varchar2, p_seq number) return number is
        l_id number := next_id;
    begin
        wwv_flow_imp_page.create_page_plug(
            p_id                       => l_id,
            p_plug_name                => p_name,
            p_region_template_options  => '#DEFAULT#',
            p_plug_template            => C_TPL_REGION,
            p_plug_display_sequence    => p_seq,
            p_attributes               => wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(
                                              'expand_shortcuts', 'N',
                                              'output_as', 'HTML')).to_clob);
        return l_id;
    end region_form;

    function ir(p_name varchar2, p_seq number, p_sql varchar2, p_static_id varchar2,
                p_items_to_submit varchar2 default null, p_rows number default 15,
                p_header varchar2 default null) return number is
        l_id  number := next_id;
        l_ws  number := next_raw;
    begin
        wwv_flow_imp_page.create_page_plug(
            p_id                       => l_id,
            p_plug_name                => p_name,
            p_region_name              => p_static_id,
            p_region_template_options  => '#DEFAULT#',
            p_component_template_options => '#DEFAULT#',
            p_plug_template            => C_TPL_IR,
            p_plug_display_sequence    => p_seq,
            p_query_type               => 'SQL',
            p_plug_source              => p_sql,
            p_plug_source_type         => 'NATIVE_IR',
            p_plug_header              => p_header,
            p_ajax_items_to_submit     => p_items_to_submit,
            p_prn_content_disposition  => 'ATTACHMENT',
            p_prn_units                => 'MILLIMETERS',
            p_prn_paper_size           => 'A4',
            p_prn_width                => 297,
            p_prn_height               => 210,
            p_prn_orientation          => 'HORIZONTAL');
        wwv_flow_imp_page.create_worksheet(
            p_id                       => wwv_flow_imp.id(l_ws),
            p_max_row_count            => '1000000',
            p_max_rows_per_page        => to_char(p_rows),
            p_pagination_type          => 'ROWS_X_TO_Y',
            p_pagination_display_pos   => 'BOTTOM_RIGHT',
            p_report_list_mode         => 'TABS',
            p_lazy_loading             => false,
            p_show_detail_link         => 'N',
            p_show_notify              => 'N',
            p_download_formats         => 'CSV:HTML:XLSX',
            p_enable_mail_download     => 'N',
            p_show_help                => 'N',   -- eingebaute APEX-Hilfe ohne Rückweg in die Anwendung
            p_owner                    => 'SPM',
            p_internal_uid             => l_ws);
        g_ws_cols   := null;
        g_ws_count  := 0;
        g_ws_static := p_static_id;
        return l_id;
    end ir;

    procedure ir_col(p_column varchar2, p_label varchar2, p_type varchar2 default 'STRING',
                     p_link varchar2 default null, p_link_text varchar2 default null,
                     p_format varchar2 default null, p_hidden boolean default false,
                     p_align varchar2 default null, p_html varchar2 default null) is
        l_ident varchar2(5);
    begin
        g_ws_count := g_ws_count + 1;
        l_ident := case when g_ws_count <= 26 then chr(64 + g_ws_count)
                        else chr(64 + trunc((g_ws_count - 1) / 26)) || chr(65 + mod(g_ws_count - 1, 26)) end;
        wwv_flow_imp_page.create_worksheet_column(
            p_id                  => next_id,
            p_db_column_name      => p_column,
            p_display_order       => g_ws_count * 10,
            p_column_identifier   => l_ident,
            p_column_label        => p_label,
            p_column_link         => p_link,
            p_column_linktext     => p_link_text,
            p_column_html_expression => p_html,
            p_column_type         => p_type,
            p_display_text_as     => case when p_hidden then 'HIDDEN_ESCAPE_SC'
                                          when p_html is not null then 'WITHOUT_MODIFICATION'
                                          else 'ESCAPE_SC' end,
            p_heading_alignment   => nvl(p_align, case when p_type = 'NUMBER' then 'RIGHT' else 'LEFT' end),
            p_column_alignment    => nvl(p_align, case when p_type = 'NUMBER' then 'RIGHT' else 'LEFT' end),
            p_format_mask         => p_format,
            p_tz_dependent        => 'N',
            p_use_as_row_header   => 'N');
        if not p_hidden then
            g_ws_cols := g_ws_cols || case when g_ws_cols is not null then ':' end || p_column;
        end if;
    end ir_col;

    procedure ir_end(p_sort_column varchar2 default null, p_sort_desc boolean default false) is
        l_id number := next_raw;
    begin
        wwv_flow_imp_page.create_worksheet_rpt(
            p_id                 => wwv_flow_imp.id(l_id),
            p_application_user   => 'APXWS_DEFAULT',
            p_report_seq         => 10,
            p_report_alias       => to_char(mod(l_id, 1000000000)),
            p_status             => 'PUBLIC',
            p_is_default         => 'Y',
            p_report_columns     => g_ws_cols,
            p_sort_column_1      => p_sort_column,
            p_sort_direction_1   => case when p_sort_column is not null
                                         then case when p_sort_desc then 'DESC' else 'ASC' end end);
    end ir_end;

    procedure item(p_name varchar2, p_region number, p_seq number, p_label varchar2 default null,
                   p_type varchar2 default 'TEXT', p_lov varchar2 default null, p_required boolean default false,
                   p_help varchar2 default null, p_readonly_when varchar2 default null,
                   p_new_row boolean default true, p_span number default null, p_null_text varchar2 default null) is
        l_display varchar2(40);
        l_attr    clob;
    begin
        case p_type
            when 'TEXT' then
                l_display := 'NATIVE_TEXT_FIELD';
                l_attr := wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(
                    'disabled', 'N', 'submit_when_enter_pressed', 'N', 'subtype', 'TEXT', 'trim_spaces', 'BOTH')).to_clob;
            when 'NUMBER' then
                l_display := 'NATIVE_NUMBER_FIELD';
                l_attr := wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(
                    'number_alignment', 'left', 'virtual_keyboard', 'decimal')).to_clob;
            when 'SELECT' then
                l_display := 'NATIVE_SELECT_LIST';
                l_attr := wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(
                    'page_action_on_selection', 'NONE')).to_clob;
            when 'TEXTAREA' then
                l_display := 'NATIVE_TEXTAREA';
                l_attr := wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(
                    'auto_height', 'N', 'character_counter', 'N', 'resizable', 'Y', 'trim_spaces', 'BOTH')).to_clob;
            when 'HIDDEN' then
                l_display := 'NATIVE_HIDDEN';
                l_attr := wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2('value_protected', 'N')).to_clob;
            when 'DISPLAY' then
                l_display := 'NATIVE_DISPLAY_ONLY';
                l_attr := wwv_flow_t_plugin_attributes(wwv_flow_t_varchar2(
                    'based_on', 'VALUE', 'format', 'PLAIN', 'send_on_page_submit', 'Y', 'show_line_breaks', 'Y')).to_clob;
        end case;

        wwv_flow_imp_page.create_page_item(
            p_id                    => next_id,
            p_name                  => p_name,
            p_item_sequence         => p_seq,
            p_item_plug_id          => p_region,
            p_prompt                => p_label,
            p_display_as            => l_display,
            p_lov                   => p_lov,
            p_lov_display_null      => case when p_type = 'SELECT' and p_null_text is not null then 'YES' else 'NO' end,
            p_lov_null_text         => p_null_text,
            p_cSize                 => case when p_type in ('TEXT', 'NUMBER') then 30 end,
            p_cMaxlength            => case when p_type = 'TEXT' then 4000 end,
            p_cHeight               => case when p_type = 'TEXTAREA' then 4 end,
            p_begin_on_new_line     => case when p_new_row then 'Y' else 'N' end,
            p_colspan               => p_span,
            p_is_required           => p_required,
            p_field_template        => case when p_type <> 'HIDDEN'
                                            then case when p_required then C_TPL_LABEL_R else C_TPL_LABEL end end,
            p_item_template_options => '#DEFAULT#',
            p_help_text             => p_help,
            p_read_only_when        => p_readonly_when,
            p_read_only_when_type   => case when p_readonly_when is not null then 'ITEM_IS_NOT_NULL' end,
            p_is_persistent         => 'Y',
            p_protection_level      => 'N',
            p_attributes            => l_attr);
    end item;

    function button(p_name varchar2, p_label varchar2, p_region number, p_seq number,
                    p_hot boolean default false, p_action varchar2 default 'SUBMIT',
                    p_url varchar2 default null, p_confirm varchar2 default null,
                    p_position varchar2 default 'NEXT', p_icon varchar2 default null) return number is
        l_id number := next_id;
    begin
        wwv_flow_imp_page.create_page_button(
            p_id                       => l_id,
            p_button_sequence          => p_seq,
            p_button_plug_id           => p_region,
            p_button_name              => p_name,
            p_button_action            => p_action,
            p_button_template_options  => '#DEFAULT#',
            p_button_template_id       => C_TPL_BUTTON,
            p_button_is_hot            => case when p_hot then 'Y' else 'N' end,
            p_button_image_alt         => p_label,
            p_button_position          => p_position,
            p_button_redirect_url      => p_url,
            p_confirm_message          => p_confirm,
            p_confirm_style            => case when p_confirm is not null then 'warning' end,
            p_icon_css_classes         => p_icon);
        return l_id;
    end button;

    procedure process(p_name varchar2, p_seq number, p_code varchar2, p_point varchar2 default 'AFTER_SUBMIT',
                      p_button number default null, p_success varchar2 default null,
                      p_condition_plsql varchar2 default null) is
        l_raw number := next_raw;
    begin
        wwv_flow_imp_page.create_page_process(
            p_id                       => wwv_flow_imp.id(l_raw),
            p_process_sequence         => p_seq,
            p_process_point            => p_point,
            p_process_type             => 'NATIVE_PLSQL',
            p_process_name             => p_name,
            p_process_sql_clob         => p_code,
            p_process_clob_language    => 'PLSQL',
            p_error_display_location   => 'INLINE_IN_NOTIFICATION',
            p_process_when_button_id   => p_button,
            p_process_when             => p_condition_plsql,
            p_process_when_type        => case when p_condition_plsql is not null then 'EXPRESSION' end,
            p_process_when2            => case when p_condition_plsql is not null then 'PLSQL' end,
            p_process_success_message  => p_success,
            p_internal_uid             => l_raw);
    end process;

    procedure branch(p_seq number, p_page number, p_button number default null, p_items varchar2 default null) is
    begin
        wwv_flow_imp_page.create_page_branch(
            p_id                       => next_id,
            p_branch_action            => 'f?p=&APP_ID.:' || p_page || ':&SESSION.::&DEBUG.:'
                                       || case when p_items is not null then 'RP:' || p_items else ':' end
                                       || '&success_msg=#SUCCESS_MSG#',
            p_branch_point             => 'AFTER_PROCESSING',
            p_branch_type              => 'REDIRECT_URL',
            p_branch_when_button_id    => p_button,
            p_branch_sequence          => p_seq);
    end branch;

    procedure nav(p_list_id number, p_seq number, p_label varchar2, p_page number, p_icon varchar2,
                  p_current_pages varchar2 default null) is
    begin
        wwv_flow_imp_shared.create_list_item(
            p_id                          => next_id,
            p_list_id                     => p_list_id,
            p_list_item_display_sequence  => p_seq,
            p_list_item_link_text         => p_label,
            p_list_item_link_target       => 'f?p=&APP_ID.:' || p_page || ':&APP_SESSION.::&DEBUG.:::',
            p_list_item_icon              => p_icon,
            p_list_item_current_type      => 'COLON_DELIMITED_PAGE_LIST',
            p_list_item_current_for_pages => nvl(p_current_pages, to_char(p_page)));
    end nav;

    procedure navbar(p_list_id number, p_seq number, p_label varchar2, p_page number, p_icon varchar2,
                     p_css_class varchar2 default null) is
    begin
        wwv_flow_imp_shared.create_list_item(
            p_id                          => next_id,
            p_list_id                     => p_list_id,
            p_list_item_display_sequence  => p_seq,
            p_list_item_link_text         => p_label,
            p_list_item_link_target       => 'f?p=&APP_ID.:' || p_page || ':&APP_SESSION.::&DEBUG.:::',
            p_list_item_icon              => p_icon,
            p_list_text_02                => p_css_class,
            p_list_item_current_type      => 'TARGET_PAGE');
    end navbar;

end spm_apex_builder;
/
