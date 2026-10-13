create or replace package spm_rules as
    -- Regelkonfiguration je Symbol (SPM_RULE) und Erzeugung des LILAM Rule Sets.
    --
    -- Das Rule Set enthält
    --   - je Symbol: VAL_MIN, VAL_MAX, VAL_EWMA_DEVIATION_PCT_UP/_DOWN auf SHARE_PRICE mit context = Symbol
    --     (nur aktive Instrumente mit aktiver Regelkonfiguration),
    --   - technische Regeln zum Abruflauf (Grenzwerte aus SPM_CONFIG, RULE_*).
    -- PUBLISH prüft es mit LILAM.CHECK_RULE_SET, trägt es als neue Version in LILAM_RULES ein
    -- und aktiviert es mit LILAM.SERVER_UPDATE_RULES für die Gruppe LILAM_GROUP.

    -- Fehler bei ungültiger Konfiguration
    C_ERR_RULE    constant pls_integer := -20311;
    -- Fehler beim Veröffentlichen
    C_ERR_PUBLISH constant pls_integer := -20312;

    -- Anlegen oder Ändern; NULL = Regel entfällt. Commit macht der Aufrufer.
    procedure save_rule(
        p_symbol            varchar2,
        p_val_min           number   default null,
        p_val_max           number   default null,
        p_ewma_pct_up       number   default null,
        p_ewma_pct_down     number   default null,
        p_ewma_warmup       number   default null,
        p_ewma_alpha        number   default null,
        p_severity_limit    varchar2 default 'ERROR',
        p_severity_ewma     varchar2 default 'WARN',
        p_throttle_seconds  number   default 3600,
        p_is_active         varchar2 default 'Y'
    );

    procedure delete_rule(p_symbol varchar2);

    -- Rule Set als JSON (ohne Zeitstempel: unveränderte Konfiguration ergibt denselben Text)
    function build_rule_set return clob;

    -- Liefert die aktive Version. Ist das erzeugte Rule Set mit dem aktiven identisch,
    -- entsteht keine neue Version. Committet.
    function publish(p_author varchar2 default null) return number;

    procedure publish(p_author varchar2 default null);

end spm_rules;
/
