-- Dazed Dank's occupations and traits, registered before scripts load (a definition naming an unregistered id stops script loading).
-- Always registered; the sandbox switch only hides them from character creation and turns their effects off.
DazedDankTraits = DazedDankTraits or {}
local T = DazedDankTraits

T.cultivationtech = CharacterTrait.register("dazeddank:cultivationtech")
T.budtender = CharacterTrait.register("dazeddank:budtender")
T.breeder = CharacterTrait.register("dazeddank:breeder")
T.greenthumb = CharacterTrait.register("dazeddank:greenthumb")
T.trimhand = CharacterTrait.register("dazeddank:trimhand")
T.chronic = CharacterTrait.register("dazeddank:chronic")
T.lightweight = CharacterTrait.register("dazeddank:lightweight")

DazedDankProfessions = DazedDankProfessions or {}
DazedDankProfessions.cultivationtech = CharacterProfession.register("dazeddank:cultivationtech")
DazedDankProfessions.budtender = CharacterProfession.register("dazeddank:budtender")
DazedDankProfessions.breeder = CharacterProfession.register("dazeddank:breeder")
