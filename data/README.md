# Data

- `US_Climbing_Gyms_Simple.xlsx`: the source list of US climbing gyms (name, latitude,
  longitude). `scripts/import_gyms_xlsx.py` turns it into `CHOSS/Resources/us_climbing_gyms.json`,
  which the app bundles. Re-run the script after editing the spreadsheet.
- `geonames_us_towns.csv`: US towns with population ≥ 1,000 from [GeoNames](https://www.geonames.org/)
  (cities1000, licensed CC BY 4.0), used to label each gym with its nearest town and state.
  Credit GeoNames wherever this data is shown.
