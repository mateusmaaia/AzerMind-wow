# Compact auction prices and credits

Approved direction: reduce auction clutter and place general acknowledgements in
Settings. AHledger still requires its credit next to displayed prices.

The item tooltip will show per-unit minimum and median, a short observation date
and an explicit bundled-snapshot label when applicable, followed by the required
credit. Holding Shift expands market, quantity and observation details. Changing
Shift while hovering refreshes the tooltip. Missing prices add nothing.

The existing full-text item attachment remains detailed for the AI, including
market, timestamp, snapshot status and attribution. Only tooltip presentation is
compact. No price values, consent rules or transport behavior change.

Add Settings > About & credits using existing dialog styling and back navigation.
It lists project origin, optional integrations, catalog sources and upstream
research acknowledgements, with selectable full text and URLs through Copy.
Existing license files, notices and source provenance remain distributed.

Validation covers compact versus expanded prices, unknown and zero values,
missing/failed integrations, required credit, actual tooltip modifier behavior,
credits navigation/back/dirty-settings protection and existing UI checks.
Client rendering remains subject to in-game review.
