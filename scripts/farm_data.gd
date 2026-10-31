extends RefCounted
# ALL numbers of the economy live here. New crop / product = add ONE entry below, nothing else.

# index of a crop inside the field data (0 = empty). Only ADD new crops at the END.
const CROP_IDS := ["", "wheat", "rice"]

# ready = false -> the crop can not be chosen / planted yet (its steps are not made)
# seed_kg_m2: seed needed per m2 (wheat: 4 kg per 10 shotok = 405 m2)
# yield_*: kg per m2 when harvested (10 shotok = 320 kg with fertilizer, 160 kg without) - used by the harvester later
const CROPS := {
	"wheat": {"name": "Wheat", "product": "wheat", "grow_sec": 300.0, "seed_kg_m2": 0.0099, "seed_price": 40.0,
		"yield_fert": 0.79, "yield_plain": 0.395, "ready": true,
		"col_young": Color(0.35, 0.7, 0.2), "col_ripe": Color(0.9, 0.72, 0.2)},
	"rice": {"name": "Rice", "product": "rice", "grow_sec": 300.0, "seed_kg_m2": 0.0099, "seed_price": 40.0,
		"yield_fert": 0.79, "yield_plain": 0.395, "ready": true,
		"col_young": Color(0.3, 0.7, 0.3), "col_ripe": Color(0.8, 0.78, 0.35)},
}

# things that can be stored, loaded on the trailer and sold. min / max = shop price range (coins per kg)
const PRODUCTS := {
	"wheat": {"name": "Wheat", "min": 28.0, "max": 35.0, "col": Color(0.9, 0.72, 0.2)},
	"rice": {"name": "Rice", "min": 28.0, "max": 35.0, "col": Color(0.95, 0.93, 0.8)},
}

const START_COINS := 3000.0
const TANK_L := 30.0          # sprayer tank size (liters)
const TANK_PRICE := 500.0     # coins for a full tank
const FERT_L_M2 := 0.0074     # 3 liters per 10 shotok (405 m2)
const TRAILER_CAP := 800.0    # kg
const UNLOAD_KG_S := 40.0     # warehouse unloading speed
const HARVESTER_CAP := 300.0  # kg


# ---- fuel (V20)
const FUEL_PRICE := 125.0          # coins per liter
const FUEL_TANK_TRACTOR := 150.0   # liters
const FUEL_TANK_HELI := 150.0      # liters
const TRACTOR_KM_PER_L := 50.0     # km on 1 liter (normal driving)
const HELI_KM_PER_L := 500.0       # km on 1 liter
const WORK_FUEL_MULT := 2.0        # tractor burns double while WORK is ON
const FUEL_FILL_LPS := 2.0         # liters per second at the pump (coins go down as it fills)
const FUEL_SCALE := 1.0            # the map is only 400 m: 1.0 = real distance. Raise (e.g. 20) to burn fuel faster
