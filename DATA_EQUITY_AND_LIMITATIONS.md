# Data equity and limitations

This is a **draft public resource** built from open federal data. It is an independent, unofficial prototype, not a product of Forsyth Futures. The numbers are a starting point for conversation, not conclusions about any community.

## Who federal data misses

- **Unhoused and doubled-up families.** The American Community Survey (ACS) samples addresses. People without a stable address are largely missed, and families staying with relatives may be counted in someone else's household.
- **Gender-expansive residents.** The ACS records sex as male or female only, so transgender, nonbinary and gender-expansive people are not visible in any sex breakdown here.
- **Undocumented residents and immigrant families.** Fear of government contact lowers response, so these neighbors may be undercounted.
- **Family, friend and neighbor caregivers.** The childcare module counts only licensed facilities. Much care for young children, especially infants, comes from relatives and neighbors and appears nowhere in this data.
- **Small groups.** American Indian and Alaska Native, Native Hawaiian and Pacific Islander, and some Asian and Hispanic subgroups are often too small to estimate reliably. They are flagged `suppress` rather than hidden, so their absence is visible.

## Methods caveats

- **Reliability flags.** Every number comes with a margin of error. Estimates with a coefficient of variation over 30% are flagged `suppress`, and those between 15% and 30% `use_with_caution`. Read them that way.
- **PUMS approximation.** Child Housing Cost Burden comes from microdata for three Public Use Microdata Areas (PUMAs). For Forsyth they cover exactly the county, but PUMS estimates still differ slightly from published tables because of sampling and disclosure-avoidance noise.
- **2020 data.** The Census Bureau released no standard 2020 ACS 1-year data because the pandemic disrupted collection. Trends skip 2020. 5-year estimates that include 2020 should be read with care.
- **Boundaries changed in 2020.** Census tracts changed, so tract values from before and after 2020 are not compared here.
- **Childcare supply is placeholder data.** Until real facility data is obtained, the supply side of the childcare module uses fake sample facilities, and it is labelled that way everywhere.
- **Cost of care** uses a state subsidy reimbursement rate, not the price every family pays.

## An invitation

The measures are shown side by side and are never combined into a score or a ranking of neighborhoods. People who live in these places know things this data cannot show. We invite residents, caregivers and organizations to interpret these numbers with us, to say what is missing, and to tell us where the data does not match lived experience.
