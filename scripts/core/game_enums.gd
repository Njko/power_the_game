class_name GameEnums

enum PlayerColor {
	RED,
	GREEN,
	YELLOW,
	BLUE,
	MERCENARY,  # Pour le mode 3 joueurs
	NONE
}

enum UnitType {
	POWER,
	SOLDIER,
	TANK,
	FIGHTER,      # Chasseur
	DESTROYER,
	REGIMENT,
	HEAVY_TANK,   # Char d'Assaut
	BOMBER,       # Bombardier
	CRUISER,      # Croiseur
	MEGA_MISSILE,
	FLAG
}

enum SectorType {
	LAND,       # Terrestre intérieur
	COASTAL,    # Terrestre côtier
	SEA,        # Maritime
	ISLAND,     # Île
	HQ          # Quartier Général
}

enum OrderType {
	MOVE,
	EXCHANGE
}

enum GamePhase {
	SETUP,
	PLANNING,        # 1° Préparation des ordres
	EXECUTION,       # 2° Exécution des ordres
	CONFLICT,        # 3° Résolution des conflits
	CAPTURE_PIECES,  # 4° Capture des pièces
	COLLECT_POWER,   # 5° Collecte des Power
	CAPTURE_FLAGS,   # 6° Capture des Drapeaux
	GAME_OVER
}

# Groupe auquel appartient chaque unité
static func get_unit_group(unit_type: UnitType) -> int:
	match unit_type:
		UnitType.SOLDIER, UnitType.TANK, UnitType.FIGHTER, UnitType.DESTROYER:
			return 1
		UnitType.REGIMENT, UnitType.HEAVY_TANK, UnitType.BOMBER, UnitType.CRUISER:
			return 2
		_:
			return 0

# Puissance de combat de chaque unité
static func get_unit_power(unit_type: UnitType) -> int:
	match unit_type:
		UnitType.POWER: return 0
		UnitType.SOLDIER: return 2
		UnitType.TANK: return 3
		UnitType.FIGHTER: return 5
		UnitType.DESTROYER: return 10
		UnitType.REGIMENT: return 20
		UnitType.HEAVY_TANK: return 30
		UnitType.BOMBER: return 25
		UnitType.CRUISER: return 50
		UnitType.MEGA_MISSILE: return 0
		UnitType.FLAG: return 0
		_: return 0

# Déplacement maximum de chaque unité
static func get_unit_max_move(unit_type: UnitType) -> int:
	match unit_type:
		UnitType.SOLDIER, UnitType.REGIMENT: return 2
		UnitType.TANK, UnitType.HEAVY_TANK: return 3
		UnitType.FIGHTER, UnitType.BOMBER: return 5
		UnitType.DESTROYER, UnitType.CRUISER: return 1
		_: return 0

# Correspondance groupe 1 -> groupe 2 (échange 3 pour 1)
static func get_upgrade_type(unit_type: UnitType) -> UnitType:
	match unit_type:
		UnitType.SOLDIER: return UnitType.REGIMENT
		UnitType.TANK: return UnitType.HEAVY_TANK
		UnitType.FIGHTER: return UnitType.BOMBER
		UnitType.DESTROYER: return UnitType.CRUISER
		_: return unit_type

# Correspondance groupe 2 -> groupe 1 (décomposition)
static func get_downgrade_type(unit_type: UnitType) -> UnitType:
	match unit_type:
		UnitType.REGIMENT: return UnitType.SOLDIER
		UnitType.HEAVY_TANK: return UnitType.TANK
		UnitType.BOMBER: return UnitType.FIGHTER
		UnitType.CRUISER: return UnitType.DESTROYER
		_: return unit_type

# Coût en Power pour acheter une unité (= sa puissance)
static func get_unit_cost(unit_type: UnitType) -> int:
	return get_unit_power(unit_type)

# Nom d'affichage de l'unité
static func get_unit_name(unit_type: UnitType) -> String:
	match unit_type:
		UnitType.POWER: return "Power"
		UnitType.SOLDIER: return "Soldat"
		UnitType.TANK: return "Tank"
		UnitType.FIGHTER: return "Chasseur"
		UnitType.DESTROYER: return "Destroyer"
		UnitType.REGIMENT: return "Régiment"
		UnitType.HEAVY_TANK: return "Char d'Assaut"
		UnitType.BOMBER: return "Bombardier"
		UnitType.CRUISER: return "Croiseur"
		UnitType.MEGA_MISSILE: return "Méga-Missile"
		UnitType.FLAG: return "Drapeau"
		_: return "Inconnu"

# Abréviations pour les ordres
static func get_unit_abbreviation(unit_type: UnitType) -> String:
	match unit_type:
		UnitType.POWER: return "P"
		UnitType.SOLDIER: return "S"
		UnitType.TANK: return "T"
		UnitType.FIGHTER: return "C"
		UnitType.DESTROYER: return "D"
		UnitType.REGIMENT: return "R"
		UnitType.HEAVY_TANK: return "A"
		UnitType.BOMBER: return "B"
		UnitType.CRUISER: return "CR"
		UnitType.MEGA_MISSILE: return "M"
		UnitType.FLAG: return "DR"
		_: return "?"

# Vérifie si une unité est terrestre (ne peut pas aller en mer)
static func is_land_unit(unit_type: UnitType) -> bool:
	return unit_type in [
		UnitType.SOLDIER, UnitType.REGIMENT,
		UnitType.TANK, UnitType.HEAVY_TANK
	]

# Vérifie si une unité est aérienne
static func is_air_unit(unit_type: UnitType) -> bool:
	return unit_type in [UnitType.FIGHTER, UnitType.BOMBER]

# Vérifie si une unité est navale
static func is_naval_unit(unit_type: UnitType) -> bool:
	return unit_type in [UnitType.DESTROYER, UnitType.CRUISER]

# Couleurs d'affichage des joueurs
static func get_player_color(player: PlayerColor) -> Color:
	match player:
		PlayerColor.RED: return Color(0.9, 0.2, 0.2)
		PlayerColor.GREEN: return Color(0.2, 0.8, 0.2)
		PlayerColor.YELLOW: return Color(0.9, 0.9, 0.2)
		PlayerColor.BLUE: return Color(0.2, 0.4, 0.9)
		PlayerColor.MERCENARY: return Color(0.6, 0.6, 0.6)
		_: return Color.WHITE
