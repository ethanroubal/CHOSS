# Data

- `US_Climbing_Gyms_Simple.xlsx`: the source list of US climbing gyms (name, latitude,
  longitude). `scripts/import_gyms_xlsx.py` turns it into `CHOSS/Resources/us_climbing_gyms.json`,
  which the app bundles. Re-run the script after editing the spreadsheet.
- `US_Climbing_Areas.xlsx`: the source list of US outdoor climbing areas (name, state, latitude,
  longitude, climbing type). `scripts/import_crags_xlsx.py` turns it into
  `CHOSS/Resources/us_climbing_areas.json`. Known coordinate errors are corrected in the script's
  `COORDINATE_FIXES` (the spreadsheet is left as-is).
- `geonames_us_towns.csv`: US towns with population ≥ 1,000 from [GeoNames](https://www.geonames.org/)
  (cities1000, licensed CC BY 4.0), used to label each gym and crag with its nearest town (and each gym with its state).
  Credit GeoNames wherever this data is shown.
