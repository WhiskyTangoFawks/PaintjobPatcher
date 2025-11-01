There are two configuration files that come with FPD: Config.ini, which contains general configurations, and Faction.ini, which has the configuration for the factions to be distributed.

Filters
Most of the configuration options are filters. A configuration filter is a comma seperated list of values that are processed in order when evaluating a given record and deciding whether/how to patch. For example, the each faction has a LVLI filter, which is used to determine whether a faction keyword should be added to a levelled list based on the editorID of the levelled list. 

Filter Qualifiers
'-' Blacklist. If a filter with this qualifier matches, it will return false.
'+' Required. The compared value must match this filter, and the filter will continue evaluating
'!' Match all. If a filter reaches this value, it will return true.
'#NoProperties' - a special logic qualifier for OMODs, that detects OMODs that have no properties (which are pretty much always default skin omods)

Config.ini
This file is responsible for universal configuration options, and has the following configurable options

filter_paintjob_ap= 
OMODs are connected to WEAP and ARMO records using Attachment Points. Attachment Point keywords passing this filter will be recognized as for a paintjob.

filter_paintjob_kywd=
OMODs have filter keywords that control what they can be attached to. Only OMODs with filter keywords passing this filter are recognized as paintjobs

filter_allow_redistribute=
By default, the script will not redistribute paintjobs that are already applied to a WEAP or ARMO record. This to prevent the patcher from distributing things that are already used. Paintjobs passing this filter will ignore this rule.

filter_eval_furn=
only FURN records passing this filter will be processed

filter_eval_item=
only WEAP and ARMO records passing this filter will be processed

filter_eval_lvli=
only LVLI records passing this filter will be processed

filter_eval_omod=
only OMOD records passing this filter will be processed

Factions.ini
Each section is a configurable faction. A faction can also be the default, or epic "faction", which means they will be applied to the default, and epic templates respectively.

is_default
is_epic
these values control whether the list will be distributed as a default or epic, respectively.

keyword
If configured, instead of generating a new keyword, the patcher will use an existing one. Good for factions that already have some sort of paintjob distribution.

alt_keywords
If a faction has multiple pre-existing distribution keywords, the alternate ones should be here. This is so the script knows if an item already has faction templates, and it doesn't need add new faction templates for it that faction. For example, the Brotherhood of Steel uses a series of Rank related keywords, and the script needs to identify those in order to know that an item already has BoS related skins applied.

filter_lvli
Used to filter LVLIs for addition of the faction filter keyword

filter_paintjob
Used to filter OMODS that will be distributed with this faction

filter_item
Used to filter the item type that will have faction templates generated for this faction
In addition to just checking the Name (for paintjobs) or the record EditorId (for everything else) for contains value, there are a few additional filter options for filter_item.
signature:ARMO
signature filters for record type, mainly useful if you only want a faction to apply to WEAP or ARMO records.
keyword:ObjectTypeArmor
Checks the item for the presence of the keyword, (can be any keyword, not just ObjectTypeArmor)
