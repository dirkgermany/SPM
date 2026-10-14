create or replace package body spm_watchlist as

    C_ERR constant pls_integer := -20201;

    function normalize_symbol(p_symbol varchar2) return varchar2 is
    begin
        return upper(regexp_replace(p_symbol, '[[:space:]]', ''));
    end normalize_symbol;

    function save_instrument(
        p_symbol           varchar2,
        p_provider_code    varchar2,
        p_provider_symbol  varchar2,
        p_currency         varchar2,
        p_name             varchar2 default null,
        p_exchange         varchar2 default null,
        p_is_active        varchar2 default 'Y'
    ) return number is
        l_symbol   spm_instrument.symbol%type;
        l_currency spm_instrument.currency%type := upper(trim(p_currency));
        l_provider spm_instrument.provider_code%type := upper(trim(p_provider_code));
        l_count    pls_integer;
        l_id       spm_instrument.instrument_id%type;
    begin
        if length(normalize_symbol(p_symbol)) > 20
           or not regexp_like(normalize_symbol(p_symbol), '^[A-Z0-9][A-Z0-9.-]{0,19}$') then
            raise_application_error(C_ERR, 'Ungültiges Symbol: 1 bis 20 Zeichen A-Z, 0-9, Punkt, Bindestrich');
        end if;
        l_symbol := normalize_symbol(p_symbol);

        if trim(p_provider_symbol) is null or length(trim(p_provider_symbol)) > 40 then
            raise_application_error(C_ERR, 'Provider-Symbol fehlt oder ist länger als 40 Zeichen');
        end if;
        if l_currency is null or not regexp_like(l_currency, '^[A-Z]{3}$') then
            raise_application_error(C_ERR, 'Währung als ISO-Code mit 3 Buchstaben angeben (z. B. EUR)');
        end if;
        if nvl(p_is_active, '?') not in ('Y', 'N') then
            raise_application_error(C_ERR, 'Aktiv-Kennzeichen muss Y oder N sein');
        end if;

        select count(*) into l_count from spm_provider where provider_code = l_provider;
        if l_count = 0 then
            raise_application_error(C_ERR, 'Unbekannter Provider: ' || l_provider);
        end if;

        merge into spm_instrument i
        using (select l_symbol sym from dual) s
        on (i.symbol = s.sym)
        when matched then update set
            i.provider_code   = l_provider,
            i.provider_symbol = trim(p_provider_symbol),
            i.instrument_name = p_name,
            i.exchange        = p_exchange,
            i.currency        = l_currency,
            i.is_active       = p_is_active,
            i.updated_at      = systimestamp
        when not matched then insert
            (symbol, provider_code, provider_symbol, instrument_name, exchange, currency, is_active)
        values
            (l_symbol, l_provider, trim(p_provider_symbol), p_name, p_exchange, l_currency, p_is_active);

        select instrument_id into l_id from spm_instrument where symbol = l_symbol;
        return l_id;
    exception
        when dup_val_on_index then
            raise_application_error(C_ERR, 'Provider-Symbol ' || trim(p_provider_symbol)
                                         || ' ist beim Provider bereits einem anderen Symbol zugeordnet');
    end save_instrument;

    procedure save_instrument(
        p_symbol           varchar2,
        p_provider_code    varchar2,
        p_provider_symbol  varchar2,
        p_currency         varchar2,
        p_name             varchar2 default null,
        p_exchange         varchar2 default null,
        p_is_active        varchar2 default 'Y'
    ) is
        l_id number;
    begin
        l_id := save_instrument(p_symbol, p_provider_code, p_provider_symbol, p_currency,
                                p_name, p_exchange, p_is_active);
    end save_instrument;

    procedure set_active(p_symbol varchar2, p_is_active varchar2) is
    begin
        if nvl(p_is_active, '?') not in ('Y', 'N') then
            raise_application_error(C_ERR, 'Aktiv-Kennzeichen muss Y oder N sein');
        end if;
        update spm_instrument
        set    is_active = p_is_active, updated_at = systimestamp
        where  symbol = normalize_symbol(p_symbol);
        if sql%rowcount = 0 then
            raise_application_error(C_ERR, 'Symbol nicht in der Watchlist: ' || normalize_symbol(p_symbol));
        end if;
    end set_active;

    function delete_history(p_symbol varchar2) return number is
        l_symbol spm_instrument.symbol%type := normalize_symbol(p_symbol);
        l_scope  varchar2(100) := spm_cfg.get_text('LILAM_BASELINE_SCOPE', 'SPM');
        l_id     spm_instrument.instrument_id%type;
        l_count  number;
    begin
        begin
            select instrument_id into l_id from spm_instrument where symbol = l_symbol;
        exception
            when no_data_found then
                raise_application_error(C_ERR, 'Symbol nicht in der Watchlist: ' || l_symbol);
        end;

        -- kein Abruflauf gleichzeitig, sonst schreibt er Kurs und Baseline sofort wieder
        if not spm_poll.acquire_lock then
            raise_application_error(C_ERR, 'Ein Abruflauf ist aktiv; bitte gleich noch einmal versuchen');
        end if;

        begin
            delete from spm_price where instrument_id = l_id;
            l_count := sql%rowcount;

            update spm_instrument
            set    last_fetch_at = null, last_fetch_status = null, last_fetch_message = null,
                   updated_at = systimestamp
            where  instrument_id = l_id;

            lilam.reset_baseline(l_scope, spm_poll.C_ACT_SHARE_PRICE,   l_symbol);
            lilam.reset_baseline(l_scope, spm_poll.C_ACT_QUOTE_AGE,     l_symbol);
            lilam.reset_baseline(l_scope, spm_poll.C_ACT_PROVIDER_CALL, l_symbol);

            spm_poll.release_lock;
        exception
            when others then
                spm_poll.release_lock;
                raise;
        end;

        return l_count;
    end delete_history;

end spm_watchlist;
/
