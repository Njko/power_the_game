class_name AIPlayer
extends RefCounted

## IA stratégique pour le jeu Power.
## Phases stratégiques: DEVELOPPER, ATTAQUER, CAPTURER, DEFENDRE
## Sélection de cible unique: concentrer les forces sur l'ennemi le plus faible.
## Coordination des unités: point de ralliement avant assaut groupé.

enum ModeStrategique {
	DEVELOPPER,  # Tours 1-5 ou peu d'unités: déployer, acheter, positionner
	ATTAQUER,    # Mi-partie: avancer coordonné vers le QG cible
	CAPTURER,    # Assez d'unités proches du QG ennemi: rush infanterie
	DEFENDRE,    # QG menacé: défense proportionnelle
}

var color: GameEnums.PlayerColor
var game_state: GameState
var _rng := RandomNumberGenerator.new()
var _secteurs_rebond: Dictionary = {}  # sector_id -> nombre de rebonds consécutifs
var _derniers_ordres: Array = []  # Sauvegarde des ordres du tour précédent

func _init(p_color: GameEnums.PlayerColor, p_state: GameState) -> void:
	color = p_color
	game_state = p_state
	_rng.randomize()

func signaler_rebond(sector_id: String) -> void:
	## Appelé par le game_manager quand une unité de cette couleur rebondit.
	if sector_id not in _secteurs_rebond:
		_secteurs_rebond[sector_id] = 0
	_secteurs_rebond[sector_id] += 1

func fin_tour() -> void:
	## Appelé en fin de tour pour mettre à jour la mémoire.
	# Oublier les rebonds anciens (> 3 tours sans rebond)
	var a_supprimer: Array[String] = []
	for sid in _secteurs_rebond:
		_secteurs_rebond[sid] -= 1
		if _secteurs_rebond[sid] <= 0:
			a_supprimer.append(sid)
	for sid in a_supprimer:
		_secteurs_rebond.erase(sid)

func _est_secteur_rebond(sector_id: String) -> bool:
	## Retourne true si ce secteur a causé un rebond récemment.
	return sector_id in _secteurs_rebond

func generate_orders() -> Array[Order]:
	var orders: Array[Order] = []
	var unites_ordonnees: Array[UnitData] = []

	var mode := _evaluer_mode()
	var cible := _choisir_cible_principale()

	# Priorité 1: Lancer les méga-missiles existants (toujours, quel que soit le mode)
	_lancer_missiles(orders, unites_ordonnees)

	# Priorité 2: Échanges d'amélioration (3 petites → 1 grosse) si utile
	_ameliorer_unites(orders)

	# Priorité 3: Déployer la réserve (max 2 ordres)
	_deployer_reserve(orders)

	# Priorité 4: Acheter des soldats si Power disponibles (max 2 ordres)
	_acheter_soldats(orders)

	match mode:
		ModeStrategique.CAPTURER:
			_rush_infanterie_vers_qg(orders, unites_ordonnees, cible)
			_avancer_troupes_coordonnees(orders, unites_ordonnees, cible)
		ModeStrategique.DEFENDRE:
			_defendre_qg(orders, unites_ordonnees)
			_avancer_troupes_coordonnees(orders, unites_ordonnees, cible)
		ModeStrategique.ATTAQUER:
			_avancer_troupes_coordonnees(orders, unites_ordonnees, cible)
		ModeStrategique.DEVELOPPER:
			_avancer_troupes_coordonnees(orders, unites_ordonnees, cible)

	# Raids aériens sur territoires ennemis de valeur
	_raids_aeriens(orders, unites_ordonnees, cible)

	# Positionnement naval
	_positionner_navires(orders, unites_ordonnees, cible)

	# Création de méga-missile si possible (puissance >= 100)
	_creer_missile(orders)

	# Fallback: au moins un mouvement
	if orders.is_empty():
		_mouvement_fallback(orders, unites_ordonnees)

	return orders


# ===== ÉVALUATION STRATÉGIQUE =====

func _evaluer_mode() -> ModeStrategique:
	var round_num: int = game_state.current_round

	# Évaluer la menace sur notre QG
	var mon_qg_id := _get_mon_qg_id()
	var menace := _niveau_menace(mon_qg_id)
	var defense := _niveau_defense(mon_qg_id)

	# Mode DEFENDRE: seulement si la menace dépasse la défense
	if menace > 0 and menace > defense:
		return ModeStrategique.DEFENDRE

	# Mode DEVELOPPER: début de partie ou peu d'unités
	var puissance_plateau := _puissance_plateau(color)
	if round_num <= 4 or puissance_plateau < 20:
		return ModeStrategique.DEVELOPPER

	# Mode CAPTURER: assez d'infanterie proche d'un QG ennemi
	var cible := _choisir_cible_principale()
	if cible != GameEnums.PlayerColor.NONE:
		var qg_cible := _get_qg_id(cible)
		var puissance_proche := _puissance_amie_proche(qg_cible, 3)
		var infanterie_proche := _compter_infanterie_proche(qg_cible, 3)
		if infanterie_proche >= 1 and puissance_proche >= 20:
			return ModeStrategique.CAPTURER

	return ModeStrategique.ATTAQUER


func _choisir_cible_principale() -> GameEnums.PlayerColor:
	## Choisir l'ennemi actif le plus faible (puissance plateau la plus basse).
	var meilleure_cible := GameEnums.PlayerColor.NONE
	var meilleure_puissance := 999999

	for ennemi in game_state.player_order:
		if ennemi == color:
			continue
		var joueur := game_state.get_player(ennemi)
		if joueur == null or joueur.is_eliminated:
			continue

		var puissance := _puissance_plateau(ennemi)
		if puissance < meilleure_puissance:
			meilleure_puissance = puissance
			meilleure_cible = ennemi

	return meilleure_cible


# ===== FONCTIONS D'ÉVALUATION =====

func _puissance_plateau(couleur: GameEnums.PlayerColor) -> int:
	## Somme de la puissance de toutes les unités sur le plateau pour cette couleur.
	var total := 0
	for unite in game_state.all_units:
		if unite.owner == couleur and not unite.in_reserve and unite.sector_id != "":
			total += unite.get_power()
	return total

func _niveau_menace(qg_id: String) -> int:
	## Somme de la puissance ennemie à distance <= 2 du QG.
	var total := 0
	var secteurs_proches := game_state.board.get_reachable_sectors(qg_id, GameEnums.UnitType.SOLDIER, 2)
	# Inclure aussi le QG lui-même
	secteurs_proches.append(qg_id)

	for sid in secteurs_proches:
		var secteur := game_state.board.get_sector(sid)
		if secteur == null:
			continue
		for unite in secteur.units:
			if unite.owner != color and unite.unit_type != GameEnums.UnitType.FLAG:
				total += unite.get_power()
	return total

func _niveau_defense(qg_id: String) -> int:
	## Somme de la puissance amie à distance <= 2 du QG.
	var total := 0
	var secteurs_proches := game_state.board.get_reachable_sectors(qg_id, GameEnums.UnitType.SOLDIER, 2)
	secteurs_proches.append(qg_id)

	for sid in secteurs_proches:
		var secteur := game_state.board.get_sector(sid)
		if secteur == null:
			continue
		for unite in secteur.units:
			if unite.owner == color and unite.unit_type != GameEnums.UnitType.FLAG:
				total += unite.get_power()
	return total

func _puissance_amie_proche(secteur_id: String, distance_max: int) -> int:
	## Puissance amie dans un rayon donné autour d'un secteur.
	var total := 0
	var secteurs := game_state.board.get_reachable_sectors(secteur_id, GameEnums.UnitType.SOLDIER, distance_max)
	secteurs.append(secteur_id)

	for sid in secteurs:
		var secteur := game_state.board.get_sector(sid)
		if secteur == null:
			continue
		for unite in secteur.units:
			if unite.owner == color and unite.unit_type != GameEnums.UnitType.FLAG:
				total += unite.get_power()
	return total

func _compter_infanterie_proche(secteur_id: String, distance_max: int) -> int:
	## Nombre d'unités d'infanterie (SOLDIER ou REGIMENT) à portée.
	var total := 0
	var secteurs := game_state.board.get_reachable_sectors(secteur_id, GameEnums.UnitType.SOLDIER, distance_max)
	secteurs.append(secteur_id)

	for sid in secteurs:
		var secteur := game_state.board.get_sector(sid)
		if secteur == null:
			continue
		for unite in secteur.units:
			if unite.owner == color and (unite.unit_type == GameEnums.UnitType.SOLDIER or unite.unit_type == GameEnums.UnitType.REGIMENT):
				total += 1
	return total


# ===== LANCEMENT DE MÉGA-MISSILES =====

func _lancer_missiles(orders: Array[Order], moved: Array[UnitData]) -> void:
	if orders.size() >= 5:
		return

	for unite in _get_mes_unites_plateau():
		if orders.size() >= 5:
			break
		if unite.unit_type != GameEnums.UnitType.MEGA_MISSILE:
			continue
		if unite in moved:
			continue

		var meilleure_cible := ""
		var meilleur_score := 0

		for sector_id in game_state.board.sectors:
			var secteur: Sector = game_state.board.get_sector(sector_id)
			if secteur == null:
				continue

			var a_ennemi := false
			var a_ami := false
			var puissance_ennemie := 0
			for u in secteur.units:
				if u.unit_type == GameEnums.UnitType.FLAG:
					continue
				if u.owner == color:
					a_ami = true
				else:
					a_ennemi = true
					puissance_ennemie += GameEnums.get_unit_power(u.unit_type)

			# Ne pas cibler ses propres unités, exiger des ennemis
			if not a_ennemi or a_ami:
				continue

			var score := puissance_ennemie
			# Bonus pour les QG ennemis
			if secteur.sector_type == GameEnums.SectorType.HQ and secteur.owner_territory != color:
				score += 20

			if score > meilleur_score:
				meilleur_score = score
				meilleure_cible = sector_id

		# Lancer si on détruit au moins 20 de puissance
		if meilleure_cible != "" and meilleur_score >= 20:
			var order := Order.create_launch(color, unite.sector_id, meilleure_cible)
			orders.append(order)
			moved.append(unite)


# ===== AMÉLIORATIONS (3 petites → 1 grosse) =====

func _ameliorer_unites(orders: Array[Order]) -> void:
	if orders.size() >= 5:
		return

	for sector_id in game_state.board.sectors:
		if orders.size() >= 5:
			break

		var secteur: Sector = game_state.board.get_sector(sector_id)
		if secteur == null:
			continue

		# Compter mes unités de groupe 1 par type
		var compteurs: Dictionary = {}
		for unite in secteur.units:
			if unite.owner == color:
				var groupe: int = GameEnums.get_unit_group(unite.unit_type)
				if groupe == 1:
					if unite.unit_type not in compteurs:
						compteurs[unite.unit_type] = 0
					compteurs[unite.unit_type] += 1

		for type_unite in compteurs:
			if compteurs[type_unite] >= 3 and orders.size() < 5:
				var resultat := GameEnums.get_upgrade_type(type_unite)
				var order := Order.create_exchange(color, [], resultat, sector_id)
				order.unit_type = type_unite
				orders.append(order)
				compteurs[type_unite] -= 3


# ===== DÉPLOIEMENT RÉSERVE =====

func _deployer_reserve(orders: Array[Order]) -> void:
	if orders.size() >= 5:
		return

	var joueur := game_state.get_player(color)
	var qg_id := _get_mon_qg_id()
	var deployes := 0

	# Prioriser les unités les plus puissantes d'abord
	var reserve_triee: Array = joueur.reserve.duplicate()
	reserve_triee.sort_custom(func(a, b): return a.get_power() > b.get_power())

	for unite in reserve_triee:
		if orders.size() >= 5 or deployes >= 2:
			break
		if unite.unit_type == GameEnums.UnitType.POWER or unite.unit_type == GameEnums.UnitType.FLAG:
			continue

		var order := Order.create_move(color, unite.unit_type, "RV", qg_id)
		orders.append(order)
		deployes += 1


# ===== ACHAT DE SOLDATS =====

func _acheter_soldats(orders: Array[Order]) -> void:
	if orders.size() >= 5:
		return

	var joueur := game_state.get_player(color)
	var power_dispo: int = joueur.get_reserve_power_count()
	var achats := 0

	while power_dispo >= 2 and orders.size() < 5 and achats < 2:
		var order := Order.create_exchange(color, [], GameEnums.UnitType.SOLDIER, "RV")
		orders.append(order)
		power_dispo -= 2
		achats += 1


# ===== RUSH INFANTERIE VERS QG ENNEMI =====

func _rush_infanterie_vers_qg(orders: Array[Order], moved: Array[UnitData], cible: GameEnums.PlayerColor) -> void:
	if orders.size() >= 5 or cible == GameEnums.PlayerColor.NONE:
		return

	var qg_cible := _get_qg_id(cible)
	if qg_cible == "":
		return

	# Collecter toute l'infanterie amie sur le plateau
	var infanterie: Array = []
	for unite in _get_mes_unites_plateau():
		if unite in moved:
			continue
		if unite.unit_type == GameEnums.UnitType.SOLDIER or unite.unit_type == GameEnums.UnitType.REGIMENT:
			infanterie.append(unite)

	# Trier par distance au QG cible (les plus proches en premier)
	infanterie.sort_custom(func(a, b):
		var da: int = game_state.board.get_distance(a.sector_id, qg_cible, a.unit_type)
		var db: int = game_state.board.get_distance(b.sector_id, qg_cible, b.unit_type)
		if da < 0:
			da = 999
		if db < 0:
			db = 999
		return da < db
	)

	for unite in infanterie:
		if orders.size() >= 5:
			break
		if unite in moved:
			continue

		var chemin: Array[String] = game_state.board.find_path(unite.sector_id, qg_cible, unite.unit_type)
		if chemin.size() < 2:
			continue

		var max_move: int = unite.get_max_move()
		var idx_cible: int = mini(max_move, chemin.size() - 1)
		var destination: String = chemin[idx_cible]

		var order := Order.create_move(color, unite.unit_type, unite.sector_id, destination)
		orders.append(order)
		moved.append(unite)


# ===== DÉFENSE DU QG (PROPORTIONNELLE) =====

func _defendre_qg(orders: Array[Order], moved: Array[UnitData]) -> void:
	if orders.size() >= 5:
		return

	var qg_id := _get_mon_qg_id()
	var rappeles := 0
	var max_rappels := 2  # Ne jamais rappeler plus de 2 unités

	# Collecter les unités pas encore proches du QG, préférer les plus fortes
	var candidats: Array = []
	for unite in _get_mes_unites_plateau():
		if unite in moved:
			continue
		if unite.unit_type == GameEnums.UnitType.FLAG:
			continue
		# Ne rappeler que les unités qui ne sont pas déjà au QG ou très proches
		var dist: int = game_state.board.get_distance(unite.sector_id, qg_id, unite.unit_type)
		if dist > 1 and dist <= unite.get_max_move() * 2:
			candidats.append(unite)

	# Trier par puissance décroissante (rappeler les plus fortes d'abord)
	candidats.sort_custom(func(a, b): return a.get_power() > b.get_power())

	for unite in candidats:
		if orders.size() >= 5 or rappeles >= max_rappels:
			break
		if unite in moved:
			continue

		var chemin: Array[String] = game_state.board.find_path(unite.sector_id, qg_id, unite.unit_type)
		if chemin.size() < 2:
			continue

		var max_move: int = unite.get_max_move()
		var idx_cible: int = mini(max_move, chemin.size() - 1)
		var destination: String = chemin[idx_cible]

		var order := Order.create_move(color, unite.unit_type, unite.sector_id, destination)
		orders.append(order)
		moved.append(unite)
		rappeles += 1


# ===== AVANCÉE COORDONNÉE =====

func _avancer_troupes_coordonnees(orders: Array[Order], moved: Array[UnitData], cible: GameEnums.PlayerColor) -> void:
	if orders.size() >= 5 or cible == GameEnums.PlayerColor.NONE:
		return

	var qg_cible := _get_qg_id(cible)
	if qg_cible == "":
		return

	# Collecter les unités terrestres non encore ordonnées
	var troupes: Array = []
	for unite in _get_mes_unites_plateau():
		if unite in moved:
			continue
		if not GameEnums.is_land_unit(unite.unit_type):
			continue
		if unite.unit_type == GameEnums.UnitType.FLAG:
			continue
		troupes.append(unite)

	if troupes.is_empty():
		return

	# Trouver le point de ralliement: secteur ami le plus proche du QG cible
	var point_ralliement := _trouver_point_ralliement(troupes, qg_cible)

	# Calculer la puissance au point de ralliement
	var puissance_ralliement := 0
	if point_ralliement != "":
		var secteur_ralliement := game_state.board.get_sector(point_ralliement)
		if secteur_ralliement != null:
			for unite in secteur_ralliement.units:
				if unite.owner == color and unite.unit_type != GameEnums.UnitType.FLAG:
					puissance_ralliement += unite.get_power()

	# Compter aussi les unités en route vers le ralliement
	for unite in troupes:
		if unite.sector_id == point_ralliement:
			continue
		var dist_ralliement: int = -1
		if point_ralliement != "":
			dist_ralliement = game_state.board.get_distance(unite.sector_id, point_ralliement, unite.unit_type)
		if dist_ralliement >= 0 and dist_ralliement <= unite.get_max_move():
			puissance_ralliement += unite.get_power()

	for unite in troupes:
		if orders.size() >= 5:
			break
		if unite in moved:
			continue

		var dist_qg: int = game_state.board.get_distance(unite.sector_id, qg_cible, unite.unit_type)
		if dist_qg < 0:
			continue  # Pas de chemin vers le QG cible

		# Si on est déjà au QG cible, ne pas bouger
		if dist_qg == 0:
			continue

		var destination := ""

		# Décision: aller au ralliement ou directement au QG?
		# Après le tour 10, ne plus attendre au ralliement — avancer même seul
		var seuil_ralliement: int = 20 if game_state.current_round <= 10 else 0
		if point_ralliement != "" and point_ralliement != unite.sector_id and seuil_ralliement > 0:
			var dist_ralliement: int = game_state.board.get_distance(unite.sector_id, point_ralliement, unite.unit_type)

			# Si l'unité est plus loin du QG que du point de ralliement,
			# et qu'on n'a pas encore assez de puissance, aller au ralliement
			if dist_ralliement >= 0 and dist_ralliement < dist_qg and puissance_ralliement < seuil_ralliement:
				destination = _avancer_vers(unite, point_ralliement)

		# Si on a assez de puissance au ralliement (>= 20) ou si on est déjà proche, avancer vers le QG
		if destination == "":
			destination = _avancer_vers(unite, qg_cible)

		if destination != "" and destination != unite.sector_id:
			var order := Order.create_move(color, unite.unit_type, unite.sector_id, destination)
			orders.append(order)
			moved.append(unite)


func _trouver_point_ralliement(troupes: Array, qg_cible: String) -> String:
	## Trouver le secteur ami le plus avancé (le plus proche du QG cible)
	## qui contient déjà des unités amies.
	var meilleur_secteur := ""
	var meilleure_dist := 999

	# Chercher parmi les secteurs contenant des unités amies terrestres
	var secteurs_vus: Dictionary = {}
	for unite in troupes:
		if unite.sector_id in secteurs_vus:
			continue
		secteurs_vus[unite.sector_id] = true

		var dist: int = game_state.board.get_distance(unite.sector_id, qg_cible, GameEnums.UnitType.SOLDIER)
		if dist > 0 and dist < meilleure_dist:
			meilleure_dist = dist
			meilleur_secteur = unite.sector_id

	return meilleur_secteur


func _avancer_vers(unite: UnitData, destination: String) -> String:
	## Retourne le secteur le plus avancé sur le chemin vers la destination,
	## en respectant le mouvement max de l'unité.
	## Évite les secteurs qui ont causé des rebonds récemment.
	var chemin: Array[String] = game_state.board.find_path(unite.sector_id, destination, unite.unit_type)
	if chemin.size() < 2:
		return ""

	var max_move: int = unite.get_max_move()
	var idx: int = mini(max_move, chemin.size() - 1)
	var cible: String = chemin[idx]

	# Si la destination directe est un secteur de rebond, reculer d'un pas
	if _est_secteur_rebond(cible) and idx > 1:
		cible = chemin[idx - 1]
	# Si même le pas précédent est un rebond, essayer un autre chemin
	if _est_secteur_rebond(cible) and cible != unite.sector_id:
		# Chercher un secteur alternatif atteignable qui rapproche du but
		var atteignables := game_state.board.get_reachable_sectors(
			unite.sector_id, unite.unit_type, max_move)
		var meilleur_alt := ""
		var meilleure_dist := 999
		for alt_id in atteignables:
			if _est_secteur_rebond(alt_id):
				continue
			if alt_id == unite.sector_id:
				continue
			var dist: int = game_state.board.get_distance(alt_id, destination, unite.unit_type)
			if dist >= 0 and dist < meilleure_dist:
				meilleure_dist = dist
				meilleur_alt = alt_id
		if meilleur_alt != "":
			cible = meilleur_alt

	return cible


# ===== RAIDS AÉRIENS =====

func _raids_aeriens(orders: Array[Order], moved: Array[UnitData], cible: GameEnums.PlayerColor) -> void:
	if orders.size() >= 5:
		return

	# Secteurs du territoire cible
	var secteurs_cible: Dictionary = {}
	if cible != GameEnums.PlayerColor.NONE:
		var prefix_cible := game_state.board.get_territory_prefix(cible)
		for i in range(9):
			secteurs_cible["%s%d" % [prefix_cible, i]] = true

	var secteurs_ennemis := _get_secteurs_territoires_ennemis()

	for unite in _get_mes_unites_plateau():
		if orders.size() >= 5:
			break
		if unite in moved:
			continue
		if not GameEnums.is_air_unit(unite.unit_type):
			continue

		var meilleure_cible := ""
		var meilleur_score := -999

		var atteignables := game_state.board.get_reachable_sectors(
			unite.sector_id, unite.unit_type, unite.get_max_move())

		for sid in atteignables:
			if sid not in secteurs_ennemis:
				continue

			var secteur := game_state.board.get_sector(sid)
			if secteur == null:
				continue

			# Score corrigé: cibler les secteurs avec de la puissance ennemie
			var puissance_ennemie := 0
			var a_amis := false
			for u in secteur.units:
				if u.owner == color:
					a_amis = true
				elif u.unit_type != GameEnums.UnitType.FLAG:
					puissance_ennemie += u.get_power()

			var score: int = puissance_ennemie

			# Bonus si c'est dans le territoire de la cible principale
			if sid in secteurs_cible:
				score += 3

			# Pénalité si le secteur contient des amis (risque de conflit)
			if a_amis:
				score -= 5

			# Bonus pour secteurs inoccupés (collecte de Power)
			if not secteur.has_units_of_player(color) and puissance_ennemie == 0:
				score += 2

			if score > meilleur_score:
				meilleur_score = score
				meilleure_cible = sid

		if meilleure_cible != "":
			var order := Order.create_move(color, unite.unit_type, unite.sector_id, meilleure_cible)
			orders.append(order)
			moved.append(unite)


# ===== POSITIONNEMENT NAVAL =====

func _positionner_navires(orders: Array[Order], moved: Array[UnitData], cible: GameEnums.PlayerColor) -> void:
	if orders.size() >= 5:
		return

	# Les navires se positionnent vers les côtes ennemies ou les îles stratégiques
	var secteurs_ennemis := _get_secteurs_territoires_ennemis()

	for unite in _get_mes_unites_plateau():
		if orders.size() >= 5:
			break
		if unite in moved:
			continue
		if not GameEnums.is_naval_unit(unite.unit_type):
			continue

		var atteignables := game_state.board.get_reachable_sectors(
			unite.sector_id, unite.unit_type, unite.get_max_move())

		var meilleure_cible := ""
		var meilleur_score := -1

		for sid in atteignables:
			if sid == unite.sector_id:
				continue
			# Éviter les secteurs de rebond
			if _est_secteur_rebond(sid):
				continue

			var secteur := game_state.board.get_sector(sid)
			if secteur == null:
				continue

			# Éviter les secteurs qui contiennent déjà un navire allié (empêche les swaps inutiles)
			var a_navire_ami := false
			for u in secteur.units:
				if u.owner == color and GameEnums.is_naval_unit(u.unit_type):
					a_navire_ami = true
					break
			if a_navire_ami:
				continue

			var score := 0

			# Préférer les secteurs côtiers ou îles proches de l'ennemi
			if secteur.sector_type == GameEnums.SectorType.ISLAND:
				score += 3

			# Préférer les secteurs adjacents à des territoires ennemis
			for adj_id in secteur.adjacent_sectors:
				if adj_id in secteurs_ennemis:
					score += 2
					break

			# Bonus si des ennemis faibles sont présents
			for u in secteur.units:
				if u.owner != color and u.unit_type != GameEnums.UnitType.FLAG:
					if u.get_power() < unite.get_power():
						score += 3

			# Éviter les secteurs avec des ennemis plus forts
			var puissance_ennemie := 0
			for u in secteur.units:
				if u.owner != color and u.unit_type != GameEnums.UnitType.FLAG:
					puissance_ennemie += u.get_power()
			if puissance_ennemie > unite.get_power():
				score -= 5

			if score > meilleur_score:
				meilleur_score = score
				meilleure_cible = sid

		if meilleure_cible != "":
			var order := Order.create_move(color, unite.unit_type, unite.sector_id, meilleure_cible)
			orders.append(order)
			moved.append(unite)


# ===== CRÉATION DE MÉGA-MISSILE =====

func _creer_missile(orders: Array[Order]) -> void:
	if orders.size() >= 4:  # Garder au moins 1 slot
		return

	for sector_id in game_state.board.sectors:
		if orders.size() >= 4:
			break

		var secteur: Sector = game_state.board.get_sector(sector_id)
		if secteur == null:
			continue

		# Collecter les unités sacrifiables
		var sacrifiables: Array = []
		var total_disponible := 0
		for unite in secteur.units:
			if unite.owner == color and unite.unit_type != GameEnums.UnitType.FLAG and unite.unit_type != GameEnums.UnitType.MEGA_MISSILE:
				var puissance: int = GameEnums.get_unit_power(unite.unit_type)
				sacrifiables.append({"type": unite.unit_type, "power": puissance})
				total_disponible += puissance

		# Seuil correct: 100 (pas 120)
		if total_disponible < 100:
			continue

		# Trier par puissance décroissante (sacrifier les plus gros = moins d'unités perdues)
		sacrifiables.sort_custom(func(a, b): return a["power"] > b["power"])

		var selectionnes: Dictionary = {}
		var puissance_selectionnee := 0
		for entree in sacrifiables:
			if puissance_selectionnee >= 100:
				break
			var ut: GameEnums.UnitType = entree["type"]
			if ut not in selectionnes:
				selectionnes[ut] = 0
			selectionnes[ut] += 1
			puissance_selectionnee += entree["power"]

		if puissance_selectionnee < 100:
			continue

		var liste_sacrifice: Array = []
		for ut in selectionnes:
			liste_sacrifice.append({"type": ut, "count": selectionnes[ut]})

		var order := Order.create_missile_exchange(color, liste_sacrifice, sector_id)
		orders.append(order)


# ===== MOUVEMENT FALLBACK =====

func _mouvement_fallback(orders: Array[Order], moved: Array[UnitData]) -> void:
	var mes_unites := _get_mes_unites_plateau()
	_melanger(mes_unites)

	for unite in mes_unites:
		if orders.size() >= 1:
			break
		if unite in moved:
			continue
		if unite.unit_type == GameEnums.UnitType.FLAG:
			continue
		if unite.get_max_move() <= 0:
			continue

		var atteignables := game_state.board.get_reachable_sectors(
			unite.sector_id, unite.unit_type, unite.get_max_move())

		if atteignables.is_empty():
			continue

		var sid: String = atteignables[_rng.randi_range(0, atteignables.size() - 1)]
		var order := Order.create_move(color, unite.unit_type, unite.sector_id, sid)
		orders.append(order)
		moved.append(unite)


# ===== UTILITAIRES =====

func _get_mes_unites_plateau() -> Array:
	var resultat := []
	for unite in game_state.all_units:
		if unite.owner == color and not unite.in_reserve and unite.sector_id != "":
			resultat.append(unite)
	return resultat

func _get_mon_qg_id() -> String:
	var prefix := game_state.board.get_territory_prefix(color)
	return "HQ_" + prefix

func _get_qg_id(couleur: GameEnums.PlayerColor) -> String:
	var prefix := game_state.board.get_territory_prefix(couleur)
	if prefix == "":
		return ""
	return "HQ_" + prefix

func _get_secteurs_territoires_ennemis() -> Dictionary:
	## Retourne un Dictionary (set) des IDs de secteurs de territoires ennemis.
	var resultat: Dictionary = {}
	for ennemi in game_state.player_order:
		if ennemi == color:
			continue
		var joueur := game_state.get_player(ennemi)
		if joueur == null or joueur.is_eliminated:
			continue

		var prefix := game_state.board.get_territory_prefix(ennemi)
		for i in range(9):
			resultat["%s%d" % [prefix, i]] = true
	return resultat

func _melanger(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
