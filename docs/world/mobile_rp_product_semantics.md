# Mobile Roleplay Product Semantics

The World mobile experience uses story language rather than storage or engine
terminology.

| Internal model | User-facing meaning |
| --- | --- |
| `PlayerPersona` | Reusable "my character" template |
| `WorldPlayerInstance` | My character inside the current story |
| `CharacterCard` | Reusable AI character template |
| `WorldCharacterInstance` | AI character inside the current story |
| `WorldSession` | Persistent story/save |
| `WorldBook` | World setting |
| `WorldScene` | Current scene |
| `WorldFeedEntry` | Roleplay transcript |

Starting a story asks only:

1. Who do you want to play?
2. Who do you want to be with?
3. Where does the story happen?

The host then creates the World/Session, player instance, character instances,
scene cast, branch, and required bindings. A WorldBook is optional.

Imports return to the same step and keep earlier selections. A first character
import may create a visible character collection in the same database transaction.
Manual character creation reuses the existing character editor with an explicit
return result, rather than replacing the onboarding route. Pending Persona and
Lore imports do not write until Start. Setup failures remove only the new session
and new assets created by that attempt; existing stories/templates remain.

The player character is an actor in the current scene. Scene Cast and player
actions therefore show `name + you`, while AI characters remain separately
controlled instances. The AI may describe natural consequences of an explicit
player action, but may not decide the player's actions, thoughts, dialogue, or
core intent.

The World Lobby prioritizes continuing stories: current scene, the character the
user is playing, present cast, and recent activity. Database terminology stays
in advanced management and compatibility detail surfaces.
