class_name GameArbiter
extends RefCounted

## Validateur de règles pour le jeu Power.
## Vérifie chaque action en temps réel contre les règles officielles.

var game_state: GameState
var _ordres_ce_tour: Dictionary = {}  # PlayerColor -> int (nombre d'ordres)
var _unites_ordonnees: Dictionary = {}  # instance_id (int) -> true
var violations: Array[String] = []


func _init(p_state: GameState) -> void:
	game_state = p_state


func debut_tour() -> void:
	## Réinitialise le suivi par tour.
	_ordres_ce_tour.clear()
	_unites_ordonnees.clear()


func valider_ordre(order: Order, player: PlayerData) -> Dictionary:
	## Valide un ordre contre les règles. Retourne {valide: bool, raison: String}.

	# Joueur éliminé
	if player.is_eliminated:
		return _violation("Joueur %s éliminé" % _nom_couleur(player.color))

	# Maximum 5 ordres par tour
	var nb_ordres: int = _ordres_ce_tour.get(player.color, 0)
	if nb_ordres >= 5:
		return _violation("Joueur %s dépasse 5 ordres (déjà %d)" % [
			_nom_couleur(player.color), nb_ordres])

	var resultat: Dictionary
	match order.order_type:
		GameEnums.OrderType.MOVE:
			resultat = _valider_ordre_deplacement(order, player)
		GameEnums.OrderType.EXCHANGE:
			resultat = _valider_ordre_echange(order, player)
		GameEnums.OrderType.LAUNCH:
			resultat = _valider_ordre_lancement(order, player)
		_:
			resultat = _violation("Type d'ordre inconnu")

	if resultat.valide:
		# Comptabiliser l'ordre
		_ordres_ce_tour[player.color] = nb_ordres + 1

	return resultat


func valider_combat(sector_id: String, winner: GameEnums.PlayerColor, powers: Dictionary) -> Dictionary:
	## Vérifie que le résultat du combat est correct.
	var sector: Sector = game_state.board.get_sector(sector_id)
	if sector == null:
		return _violation("Combat: secteur %s inexistant" % sector_id)

	# Recalculer les puissances depuis les unités du secteur
	var puissances_reelles: Dictionary = {}
	for color_key in powers:
		var couleur: GameEnums.PlayerColor = color_key
		var puissance_reelle: int = sector.get_player_power(couleur)
		puissances_reelles[couleur] = puissance_reelle
		var puissance_declaree: int = powers[couleur]
		if puissance_reelle != puissance_declaree:
			return _violation("Combat %s: puissance %s déclarée %d != réelle %d" % [
				sector_id, _nom_couleur(couleur), puissance_declaree, puissance_reelle])

	# Vérifier le gagnant
	var max_puissance := 0
	var joueurs_max: Array[GameEnums.PlayerColor] = []
	for color_key in puissances_reelles:
		var couleur: GameEnums.PlayerColor = color_key
		var p: int = puissances_reelles[couleur]
		if p > max_puissance:
			max_puissance = p
			joueurs_max = [couleur]
		elif p == max_puissance:
			joueurs_max.append(couleur)

	if joueurs_max.size() > 1:
		# Égalité — le gagnant devrait être NONE
		if winner != GameEnums.PlayerColor.NONE:
			return _violation("Combat %s: égalité mais gagnant déclaré %s" % [
				sector_id, _nom_couleur(winner)])
	else:
		if joueurs_max.size() == 1 and winner != joueurs_max[0]:
			return _violation("Combat %s: gagnant devrait être %s, déclaré %s" % [
				sector_id, _nom_couleur(joueurs_max[0]), _nom_couleur(winner)])

	return {valide = true, raison = ""}


func valider_capture_drapeau(attacker: GameEnums.PlayerColor, defender: GameEnums.PlayerColor) -> Dictionary:
	## Vérifie les conditions de capture de drapeau.
	var prefix: String = game_state.board.get_territory_prefix(defender)
	var hq_id := "HQ_" + prefix
	var hq: Sector = game_state.board.get_sector(hq_id)

	if hq == null:
		return _violation("Drapeau: QG %s inexistant" % hq_id)

	# L'attaquant a des unités dans le QG
	if not hq.has_units_of_player(attacker):
		return _violation("Drapeau: %s n'a pas d'unités dans %s" % [
			_nom_couleur(attacker), hq_id])

	# Au moins un soldat ou régiment
	var a_infanterie := false
	for unit in hq.get_units_of_player(attacker):
		if unit.unit_type == GameEnums.UnitType.SOLDIER or unit.unit_type == GameEnums.UnitType.REGIMENT:
			a_infanterie = true
			break

	if not a_infanterie:
		return _violation("Drapeau: %s n'a pas d'infanterie dans %s" % [
			_nom_couleur(attacker), hq_id])

	# Puissance strictement supérieure
	var puissance_attaquant: int = hq.get_player_power(attacker)
	var puissance_defenseur: int = hq.get_player_power(defender)

	if puissance_attaquant <= puissance_defenseur:
		return _violation("Drapeau: puissance %s (%d) <= %s (%d) dans %s" % [
			_nom_couleur(attacker), puissance_attaquant,
			_nom_couleur(defender), puissance_defenseur, hq_id])

	return {valide = true, raison = ""}


func valider_collecte_power(color: GameEnums.PlayerColor) -> Dictionary:
	## Vérifie qu'un joueur occupe au moins 1 secteur d'un territoire ennemi.
	var occupe_territoire := false

	for enemy_color in game_state.player_order:
		if enemy_color == color:
			continue
		var enemy_player: PlayerData = game_state.get_player(enemy_color)
		if enemy_player.is_eliminated:
			continue

		var prefix: String = game_state.board.get_territory_prefix(enemy_color)
		for i in range(9):
			var sector_id := "%s%d" % [prefix, i]
			var sector: Sector = game_state.board.get_sector(sector_id)
			if sector and sector.has_units_of_player(color):
				occupe_territoire = true
				break
		if occupe_territoire:
			break

	if not occupe_territoire:
		return _violation("Collecte Power: %s n'occupe aucun territoire ennemi" % _nom_couleur(color))

	return {valide = true, raison = ""}


func get_violations_count() -> int:
	return violations.size()


# =============================================
# Validation détaillée des ordres
# =============================================

func _valider_ordre_deplacement(order: Order, player: PlayerData) -> Dictionary:
	## Valide un ordre de déplacement (MOVE).

	# Déploiement depuis la réserve
	if order.from_sector == "RV":
		return _valider_deploiement_reserve(order, player)

	# Vérifier secteur source
	var from_sector: Sector = game_state.board.get_sector(order.from_sector)
	if from_sector == null:
		return _violation("Déplacement: secteur source %s inexistant" % order.from_sector)

	# Trouver l'unité correspondante
	var unite_trouvee: UnitData = null
	for unit in from_sector.units:
		if unit.owner == player.color and unit.unit_type == order.unit_type and not unit.moved_this_turn:
			var uid: int = unit.get_instance_id()
			if uid not in _unites_ordonnees:
				unite_trouvee = unit
				break

	if unite_trouvee == null:
		return _violation("Déplacement: pas de %s disponible pour %s en %s" % [
			GameEnums.get_unit_name(order.unit_type),
			_nom_couleur(player.color), order.from_sector])

	# Vérifier secteur destination
	var to_sector: Sector = game_state.board.get_sector(order.to_sector)
	if to_sector == null:
		return _violation("Déplacement: secteur destination %s inexistant" % order.to_sector)

	# Accessibilité par type d'unité
	if not to_sector.is_accessible_by(order.unit_type):
		return _violation("Déplacement: %s ne peut pas accéder à %s (type %s)" % [
			GameEnums.get_unit_name(order.unit_type), order.to_sector,
			_nom_type_secteur(to_sector.sector_type)])

	# Distance maximale
	var max_deplacement: int = GameEnums.get_unit_max_move(order.unit_type)
	var distance: int = game_state.board.get_distance(order.from_sector, order.to_sector, order.unit_type)

	if distance < 0:
		return _violation("Déplacement: pas de chemin de %s à %s pour %s" % [
			order.from_sector, order.to_sector, GameEnums.get_unit_name(order.unit_type)])

	if distance > max_deplacement:
		return _violation("Déplacement: distance %d > max %d pour %s (%s → %s)" % [
			distance, max_deplacement, GameEnums.get_unit_name(order.unit_type),
			order.from_sector, order.to_sector])

	# Pour les unités terrestres: vérifier que la destination est atteignable
	# (les îles/QG bloquent le passage, l'unité doit s'y arrêter)
	if GameEnums.is_land_unit(order.unit_type):
		var secteurs_atteignables: Array[String] = game_state.board.get_reachable_sectors(
			order.from_sector, order.unit_type, max_deplacement)
		if order.to_sector not in secteurs_atteignables:
			return _violation("Déplacement: %s inatteignable depuis %s pour %s (passage obligatoire)" % [
				order.to_sector, order.from_sector, GameEnums.get_unit_name(order.unit_type)])

	# Marquer l'unité comme ordonnée
	_unites_ordonnees[unite_trouvee.get_instance_id()] = true

	return {valide = true, raison = ""}


func _valider_deploiement_reserve(order: Order, player: PlayerData) -> Dictionary:
	## Valide un déploiement depuis la réserve vers le QG.

	# Vérifier qu'une unité du bon type existe en réserve
	var unite_trouvee: UnitData = null
	for unit in player.reserve:
		if unit.unit_type == order.unit_type and not unit.moved_this_turn:
			var uid: int = unit.get_instance_id()
			if uid not in _unites_ordonnees:
				unite_trouvee = unit
				break

	if unite_trouvee == null:
		return _violation("Déploiement: pas de %s en réserve pour %s" % [
			GameEnums.get_unit_name(order.unit_type), _nom_couleur(player.color)])

	# La destination doit être le QG du joueur
	var hq_id := "HQ_" + game_state.board.get_territory_prefix(player.color)
	if order.to_sector != hq_id:
		return _violation("Déploiement: destination %s != QG %s" % [order.to_sector, hq_id])

	# Marquer l'unité comme ordonnée
	_unites_ordonnees[unite_trouvee.get_instance_id()] = true

	return {valide = true, raison = ""}


func _valider_ordre_echange(order: Order, player: PlayerData) -> Dictionary:
	## Valide un ordre d'échange (EXCHANGE).
	var location := order.exchange_location

	# Achat depuis la réserve
	if location == "RV":
		var cout: int = GameEnums.get_unit_cost(order.exchange_result)
		var power_dispo: int = player.get_reserve_power_count()
		if power_dispo < cout:
			return _violation("Échange RV: %s a %d Power, besoin %d pour %s" % [
				_nom_couleur(player.color), power_dispo, cout,
				GameEnums.get_unit_name(order.exchange_result)])
		return {valide = true, raison = ""}

	var sector: Sector = game_state.board.get_sector(location)
	if sector == null:
		return _violation("Échange: secteur %s inexistant" % location)

	# Création de Méga-Missile
	if order.exchange_result == GameEnums.UnitType.MEGA_MISSILE:
		return _valider_creation_missile(order, player, sector)

	# Échange 3 pour 1 (upgrade)
	var type_source: GameEnums.UnitType = order.unit_type
	var type_resultat: GameEnums.UnitType = order.exchange_result
	var type_attendu: GameEnums.UnitType = GameEnums.get_upgrade_type(type_source)

	if type_resultat != type_attendu:
		return _violation("Échange: %s ne s'améliore pas en %s (attendu: %s)" % [
			GameEnums.get_unit_name(type_source),
			GameEnums.get_unit_name(type_resultat),
			GameEnums.get_unit_name(type_attendu)])

	# Compter les unités du type source appartenant au joueur
	var nb_unites := 0
	for unit in sector.units:
		if unit.owner == player.color and unit.unit_type == type_source:
			nb_unites += 1

	if nb_unites < 3:
		return _violation("Échange: %s n'a que %d %s en %s (besoin 3)" % [
			_nom_couleur(player.color), nb_unites,
			GameEnums.get_unit_name(type_source), location])

	return {valide = true, raison = ""}


func _valider_creation_missile(order: Order, player: PlayerData, sector: Sector) -> Dictionary:
	## Valide la création d'un Méga-Missile (sacrifice >= 100 de puissance).
	var puissance_totale := 0
	var unites_verifiees: Array = []

	for entry in order.exchange_units:
		var type_unite: GameEnums.UnitType = entry["type"]
		var nombre: int = entry["count"]

		# Compter les unités disponibles du type dans le secteur
		var disponibles := 0
		for unit in sector.units:
			if unit.owner == player.color and unit.unit_type == type_unite and unit not in unites_verifiees:
				disponibles += 1
				unites_verifiees.append(unit)
				if disponibles >= nombre:
					break

		if disponibles < nombre:
			return _violation("Missile: pas assez de %s en %s (%d/%d)" % [
				GameEnums.get_unit_name(type_unite), sector.id, disponibles, nombre])

		puissance_totale += GameEnums.get_unit_power(type_unite) * nombre

	# Vérifier que toutes les unités sacrifiées appartiennent au joueur
	# (déjà vérifié ci-dessus via unit.owner == player.color)

	if puissance_totale < 100:
		return _violation("Missile: puissance totale %d < 100 requise en %s" % [
			puissance_totale, sector.id])

	return {valide = true, raison = ""}


func _valider_ordre_lancement(order: Order, player: PlayerData) -> Dictionary:
	## Valide un ordre de lancement de Méga-Missile (LAUNCH).
	var from_sector: Sector = game_state.board.get_sector(order.from_sector)
	if from_sector == null:
		return _violation("Lancement: secteur source %s inexistant" % order.from_sector)

	# Trouver un Méga-Missile du joueur dans le secteur
	var missile_trouve := false
	for unit in from_sector.units:
		if unit.owner == player.color and unit.unit_type == GameEnums.UnitType.MEGA_MISSILE:
			missile_trouve = true
			break

	if not missile_trouve:
		return _violation("Lancement: pas de Méga-Missile pour %s en %s" % [
			_nom_couleur(player.color), order.from_sector])

	# Vérifier secteur cible
	var to_sector: Sector = game_state.board.get_sector(order.to_sector)
	if to_sector == null:
		return _violation("Lancement: secteur cible %s inexistant" % order.to_sector)

	return {valide = true, raison = ""}


# =============================================
# Utilitaires
# =============================================

func _violation(raison: String) -> Dictionary:
	## Enregistre et retourne une violation.
	violations.append(raison)
	return {valide = false, raison = raison}


func _nom_couleur(c: GameEnums.PlayerColor) -> String:
	match c:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		_: return "?"


func _nom_type_secteur(t: GameEnums.SectorType) -> String:
	match t:
		GameEnums.SectorType.LAND: return "terrestre"
		GameEnums.SectorType.COASTAL: return "côtier"
		GameEnums.SectorType.SEA: return "maritime"
		GameEnums.SectorType.ISLAND: return "île"
		GameEnums.SectorType.HQ: return "QG"
		_: return "inconnu"
