MoneyRails.configure do |config|
    # set the default currency
    config.default_currency = :clp

    # Register a custom currency
    config.register_currency = {
        priority:            1,
        iso_code:            "Q",
        name:                "conq Q",
        symbol:              "",
        symbol_first:        true,
        subunit:             "subQ",
        subunit_to_unit:     100,
        thousands_separator: ".",
        decimal_mark:        ","
    }

end