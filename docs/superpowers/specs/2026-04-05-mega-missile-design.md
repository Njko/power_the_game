# Spec : Implémentation du Méga-Missile

## Contexte

Le Méga-Missile est défini dans les règles originales de Power (1981) mais n'est pas encore implémenté dans le jeu. Le type `MEGA_MISSILE` existe déjà dans `GameEnums.UnitType` avec puissance 0 et nom "Méga-Missile", mais aucune logique de création, lancement ou destruction n'est codée. L'IA le skip explicitement (`ai_player.gd:113`).

## Règles originales (source : `regles_power.htm`)

- **Création** : Sacrifier des unités/Power totalisant >= 100 de puissance depuis un même secteur. L'excédent est perdu. Coûte 1 ordre.
- **Lancement** : Portée illimitée, cible n'importe quel secteur du plateau. Détruit TOUTES les unités sur le secteur cible (y compris les siennes). Les drapeaux ne sont PAS détruits. Le missile est consommé. Coûte 1 ordre.
- **Défense** : Puissance 0. Un missile non lancé peut être capturé par n'importe quelle unité ennemie.
- **Création + lancement** : Possible dans le même tour (2 ordres sur 5).

## Design technique

### 1. OrderType.LAUNCH (nouveau)

Ajout d'un nouveau type d'ordre dans `GameEnums.OrderType`.

**Fichier** : `scripts/core/game_enums.gd`
```
enum OrderType { MOVE, EXCHANGE, LAUNCH }
```

### 2. Order : nouvelles factory methods

**Fichier** : `scripts/core/order.gd`

#### `create_launch(player, from_sector, to_sector)`
- `order_type = LAUNCH`
- `unit_type = MEGA_MISSILE`
- `from_sector` = secteur où se trouve le missile
- `to_sector` = secteur cible

#### `create_missile_exchange(player, sacrificed_units, location)`
- Réutilise `OrderType.EXCHANGE` avec `exchange_result = MEGA_MISSILE`
- `exchange_units` = tableau des types d'unités sacrifiées (avec compteurs)
- `exchange_location` = secteur de création

#### `get_description()` étendu
- LAUNCH : "Méga-Missile : V3 → HQ_R" (secteur source → cible)
- EXCHANGE missile : "Création Méga-Missile (V3) — 105 Power sacrifiés"

### 3. GameManager : exécution du lancement

**Fichier** : `scripts/core/game_manager.gd`

#### `_validate_and_execute_order()` — ajouter cas LAUNCH
```
if order.order_type == GameEnums.OrderType.LAUNCH:
    return _execute_launch_order(order, player)
```

#### `_execute_launch_order(order, player)` — nouvelle fonction
1. Trouver le Méga-Missile du joueur dans `from_sector`
2. Si absent → ordre invalide
3. Retirer le missile du jeu (`game_state.remove_unit()`)
4. Détruire toutes les unités sur `to_sector` SAUF les drapeaux (`remove_unit()` pour chacune)
5. Émettre `resolution_log` avec détails (unités détruites par joueur)
6. Déclencher animation d'explosion

#### `_execute_exchange_order()` — étendre pour MEGA_MISSILE
Quand `exchange_result == MEGA_MISSILE` :
1. Calculer la puissance totale des unités sacrifiées dans le secteur
2. Vérifier total >= 100
3. Retirer les unités sacrifiées
4. Créer un `UnitData(MEGA_MISSILE, player, location)` sur le secteur

### 4. OrderPanel : UI création et lancement

**Fichier** : `scripts/ui/order_panel.gd`

#### Nouveau bouton "Créer Méga-Missile"
Ajouté dans `_build_ui()` après le bouton "Mode Échange".

#### Mode création (`_is_missile_create_mode`)
1. Le joueur clique un secteur contenant ses unités
2. Affichage d'une liste de coches (checkbox) pour chaque unité présente
3. Compteur temps réel : "Puissance totale : 87/100"
4. Bouton "Confirmer" actif quand >= 100
5. Crée un `Order.create_missile_exchange()`

#### Mode lancement (intégré dans `_try_select_unit` / `_try_set_destination`)
Quand le joueur sélectionne un Méga-Missile sur le plateau :
- Tous les secteurs du plateau sont surlignés (portée illimitée)
- Clic destination → crée `Order.create_launch()`
- Pas de vérification de distance ni d'accessibilité terrain

### 5. Animation d'explosion

**Fichier** : `scripts/board/animation_manager.gd`

#### `play_missile_explosion(from_sector, to_sector, player_color)`
1. Animation de vol : trait/flash du secteur source vers la cible
2. Explosion : flash rouge-orange pulsé sur le secteur cible (3 pulses)
3. Les unités disparaissent progressivement

### 6. UnitRenderer : icône missile

**Fichier** : `scripts/units/unit_renderer.gd`

Vérifier que `MEGA_MISSILE` a une icône distincte (fusée/missile). Ajouter si manquante.

### 7. IA : stratégie missile

**Fichier** : `scripts/ai/ai_player.gd`

#### Création
- Si la puissance totale d'unités sur un même secteur dépasse largement 100 (ex: secteur saturé), envisager la création
- Priorité basse : l'IA ne crée un missile que si elle a un avantage matériel significatif

#### Lancement
- Cible prioritaire : QG ennemi avec forte garnison (mais sans propres unités)
- Cible secondaire : concentration ennemie >= 50 de puissance
- Ne PAS cibler un secteur vide ou avec ses propres unités seules

### 8. Capture passive (déjà fonctionnel)

Le combat existant dans `_phase_conflict()` gère déjà les unités à puissance 0 : elles sont capturées lors d'un conflit perdu. Le Méga-Missile sera naturellement capturé comme n'importe quelle unité avec 0 de puissance.

## Fichiers modifiés

| Fichier | Nature du changement |
|---------|---------------------|
| `scripts/core/game_enums.gd:34-37` | Ajouter `LAUNCH` à `OrderType` |
| `scripts/core/order.gd` | Factory `create_launch()`, `create_missile_exchange()`, `get_description()` |
| `scripts/core/game_manager.gd:245-340` | `_execute_launch_order()`, étendre `_execute_exchange_order()` |
| `scripts/ui/order_panel.gd` | Bouton + modes création/lancement |
| `scripts/board/animation_manager.gd` | `play_missile_explosion()` |
| `scripts/units/unit_renderer.gd` | Icône missile (si manquante) |
| `scripts/ai/ai_player.gd:113` | Remplacer le skip par stratégie création/lancement |

## Vérification

1. **Création** : Placer 100+ de puissance sur un secteur → créer le missile → vérifier que les unités sont sacrifiées et le missile apparaît
2. **Lancement** : Lancer le missile sur un secteur occupé → vérifier destruction de toutes les unités sauf drapeaux
3. **Création + Lancement même tour** : 2 ordres consécutifs, vérifier que ça fonctionne
4. **Capture passive** : Missile non lancé sur secteur contesté → capturé par l'ennemi
5. **Missile sur secteur vide** : Lancer sur secteur vide → missile détruit, pas d'effet
6. **Drapeau survivant** : Lancer sur QG avec drapeau → drapeau reste, tout le reste détruit
7. **IA** : Vérifier que l'IA crée et lance des missiles de manière cohérente
8. **Animation** : Vérifier visuellement l'explosion
