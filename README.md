# vitalconditions-refresh

A reproducible R pipeline that refreshes public indicators for Forsyth County, NC, maps them to the **Seven Vital Conditions for Wellbeing and Justice**, flags statistical reliability (margin of error / coefficient of variation), validates every output against its source, and exports files ready for Tableau Public.

> **Independent, unofficial prototype.** This project is not affiliated with or endorsed by Forsyth Futures. It uses only open public data (U.S. Census ACS, TIGER/Line, and other public sources) and is offered as a draft public resource.

## Status

🚧 Under construction. See [`BUILD_PROMPT.md`](BUILD_PROMPT.md) for the full specification and milestones.

## Requirements

- R (≥ 4.4) and Rtools (Windows)
- Quarto
- A free Census API key stored in the `CENSUS_API_KEY` environment variable (never committed)
