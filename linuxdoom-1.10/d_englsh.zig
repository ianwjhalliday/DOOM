
const PRESSKEY = "press a key.";
const PRESSYN = "press y or n.";

pub const Strings = struct {
    // d_main.zig
    D_DEVSTR: [:0]const u8 = "Development mode ON.\n",
    D_CDROM: [:0]const u8 = "CD-ROM Version: default.cfg from c:\\doomdata\n",

    // m_menu.zig
    QUITMSG: [:0]const u8 = "are you sure you want to\nquit this great game?",
    LOADNET: [:0]const u8 = "you can't do load while in a net game!\n\n" ++ PRESSKEY,
    QLOADNET: [:0]const u8 = "you can't quickload during a netgame!\n\n" ++ PRESSKEY,
    QSAVESPOT: [:0]const u8 = "you haven't picked a quicksave slot yet!\n\n" ++ PRESSKEY,
    SAVEDEAD: [:0]const u8 = "you can't save if you aren't playing!\n\n" ++ PRESSKEY,
    QSPROMPT: [:0]const u8 = "quicksave over your game named\n\n'{s}'?\n\n" ++ PRESSYN,
    QLPROMPT: [:0]const u8 = "do you want to quickload the game named\n\n'{s}'?\n\n" ++ PRESSYN,

    NEWGAME: [:0]const u8 =
        "you can't start a new game\n" ++
        "while in a network game.\n\n" ++ PRESSKEY,

    NIGHTMARE: [:0]const u8 =
        "are you sure? this skill level\n" ++
        "isn't even remotely fair.\n\n" ++ PRESSYN,

    SWSTRING: [:0]const u8 =
        "this is the shareware version of doom.\n\n" ++
        "you need to order the entire trilogy.\n\n" ++ PRESSKEY,

    MSGOFF: [:0]const u8 = "Messages OFF",
    MSGON: [:0]const u8 = "Messages ON",
    NETEND: [:0]const u8 = "you can't end a netgame!\n\n" ++ PRESSKEY,
    ENDGAME: [:0]const u8 = "are you sure you want to end the game?\n\n" ++ PRESSYN,

    DOSY: [:0]const u8 = "(press y to quit)",

    DETAILHI: [:0]const u8 = "High detail",
    DETAILLO: [:0]const u8 = "Low detail",
    gammamsg: [5][:0]const u8 = .{
        "Gamma correction OFF",
        "Gamma correction level 1",
        "Gamma correction level 2",
        "Gamma correction level 3",
        "Gamma correction level 4",
    },
    EMPTYSTRING: [:0]const u8 = "empty slot",

    // p_inter.zig
    GOTARMOR: [:0]const u8 = "Picked up the armor.",
    GOTMEGA: [:0]const u8 = "Picked up the MegaArmor!",
    GOTHTHBONUS: [:0]const u8 = "Picked up a health bonus.",
    GOTARMBONUS: [:0]const u8 = "Picked up an armor bonus.",
    GOTSTIM: [:0]const u8 = "Picked up a stimpack.",
    GOTMEDINEED: [:0]const u8 = "Picked up a medikit that you REALLY need!",
    GOTMEDIKIT: [:0]const u8 = "Picked up a medikit.",
    GOTSUPER: [:0]const u8 = "Supercharge!",

    GOTBLUECARD: [:0]const u8 = "Picked up a blue keycard.",
    GOTYELWCARD: [:0]const u8 = "Picked up a yellow keycard.",
    GOTREDCARD: [:0]const u8 = "Picked up a red keycard.",
    GOTBLUESKUL: [:0]const u8 = "Picked up a blue skull key.",
    GOTYELWSKUL: [:0]const u8 = "Picked up a yellow skull key.",
    GOTREDSKULL: [:0]const u8 = "Picked up a red skull key.",

    GOTINVUL: [:0]const u8 = "Invulnerability!",
    GOTBERSERK: [:0]const u8 = "Berserk!",
    GOTINVIS: [:0]const u8 = "Partial Invisibility",
    GOTSUIT: [:0]const u8 = "Radiation Shielding Suit",
    GOTMAP: [:0]const u8 = "Computer Area Map",
    GOTVISOR: [:0]const u8 = "Light Amplification Visor",
    GOTMSPHERE: [:0]const u8 = "MegaSphere!",

    GOTCLIP: [:0]const u8 = "Picked up a clip.",
    GOTCLIPBOX: [:0]const u8 = "Picked up a box of bullets.",
    GOTROCKET: [:0]const u8 = "Picked up a rocket.",
    GOTROCKBOX: [:0]const u8 = "Picked up a box of rockets.",
    GOTCELL: [:0]const u8 = "Picked up an energy cell.",
    GOTCELLBOX: [:0]const u8 = "Picked up an energy cell pack.",
    GOTSHELLS: [:0]const u8 = "Picked up 4 shotgun shells.",
    GOTSHELLBOX: [:0]const u8 = "Picked up a box of shotgun shells.",
    GOTBACKPACK: [:0]const u8 = "Picked up a backpack full of ammo!",

    GOTBFG9000: [:0]const u8 = "You got the BFG9000!  Oh, yes.",
    GOTCHAINGUN: [:0]const u8 = "You got the chaingun!",
    GOTCHAINSAW: [:0]const u8 = "A chainsaw!  Find some meat!",
    GOTLAUNCHER: [:0]const u8 = "You got the rocket launcher!",
    GOTPLASMA: [:0]const u8 = "You got the plasma gun!",
    GOTSHOTGUN: [:0]const u8 = "You got the shotgun!",
    GOTSHOTGUN2: [:0]const u8 = "You got the super shotgun!",

    // p_doors.zig
    PD_BLUEO: [:0]const u8 = "You need a blue key to activate this object",
    PD_REDO: [:0]const u8 = "You need a red key to activate this object",
    PD_YELLOWO: [:0]const u8 = "You need a yellow key to activate this object",
    PD_BLUEK: [:0]const u8 = "You need a blue key to open this door",
    PD_REDK: [:0]const u8 = "You need a red key to open this door",
    PD_YELLOWK: [:0]const u8 = "You need a yellow key to open this door",

    // g_game.zig
    GGSAVED: [:0]const u8 = "game saved.",

    // hu_stuff.zig
    HUSTR_MSGU: [:0]const u8 = "[Message unsent]",

    mapnames: [45][:0]const u8 = .{
        // DOOM shareware/registered/retail (Ultimate) names.
        "E1M1: Hangar",
        "E1M2: Nuclear Plant",
        "E1M3: Toxin Refinery",
        "E1M4: Command Control",
        "E1M5: Phobos Lab",
        "E1M6: Central Processing",
        "E1M7: Computer Station",
        "E1M8: Phobos Anomaly",
        "E1M9: Military Base",

        "E2M1: Deimos Anomaly",
        "E2M2: Containment Area",
        "E2M3: Refinery",
        "E2M4: Deimos Lab",
        "E2M5: Command Center",
        "E2M6: Halls of the Damned",
        "E2M7: Spawning Vats",
        "E2M8: Tower of Babel",
        "E2M9: Fortress of Mystery",

        "E3M1: Hell Keep",
        "E3M2: Slough of Despair",
        "E3M3: Pandemonium",
        "E3M4: House of Pain",
        "E3M5: Unholy Cathedral",
        "E3M6: Mt. Erebus",
        "E3M7: Limbo",
        "E3M8: Dis",
        "E3M9: Warrens",

        "E4M1: Hell Beneath",
        "E4M2: Perfect Hatred",
        "E4M3: Sever The Wicked",
        "E4M4: Unruly Evil",
        "E4M5: They Will Repent",
        "E4M6: Against Thee Wickedly",
        "E4M7: And Hell Followed",
        "E4M8: Unto The Cruel",
        "E4M9: Fear",

        "NEWLEVEL",
        "NEWLEVEL",
        "NEWLEVEL",
        "NEWLEVEL",
        "NEWLEVEL",
        "NEWLEVEL",
        "NEWLEVEL",
        "NEWLEVEL",
        "NEWLEVEL",
    },

    mapnames2: [32][:0]const u8 = .{
        // DOOM 2 map names.
        "level 1: entryway",
        "level 2: underhalls",
        "level 3: the gantlet",
        "level 4: the focus",
        "level 5: the waste tunnels",
        "level 6: the crusher",
        "level 7: dead simple",
        "level 8: tricks and traps",
        "level 9: the pit",
        "level 10: refueling base",
        "level 11: 'o' of destruction!",

        "level 12: the factory",
        "level 13: downtown",
        "level 14: the inmost dens",
        "level 15: industrial zone",
        "level 16: suburbs",
        "level 17: tenements",
        "level 18: the courtyard",
        "level 19: the citadel",
        "level 20: gotcha!",

        "level 21: nirvana",
        "level 22: the catacombs",
        "level 23: barrels o' fun",
        "level 24: the chasm",
        "level 25: bloodfalls",
        "level 26: the abandoned mines",
        "level 27: monster condo",
        "level 28: the spirit world",
        "level 29: the living end",
        "level 30: icon of sin",

        "level 31: wolfenstein",
        "level 32: grosse",
    },

    mapnamesp: [32][:0]const u8 = .{
        // Plutonia WAD map names.
        "level 1: congo",
        "level 2: well of souls",
        "level 3: aztec",
        "level 4: caged",
        "level 5: ghost town",
        "level 6: baron's lair",
        "level 7: caughtyard",
        "level 8: realm",
        "level 9: abattoire",
        "level 10: onslaught",
        "level 11: hunted",

        "level 12: speed",
        "level 13: the crypt",
        "level 14: genesis",
        "level 15: the twilight",
        "level 16: the omen",
        "level 17: compound",
        "level 18: neurosphere",
        "level 19: nme",
        "level 20: the death domain",

        "level 21: slayer",
        "level 22: impossible mission",
        "level 23: tombstone",
        "level 24: the final frontier",
        "level 25: the temple of darkness",
        "level 26: bunker",
        "level 27: anti-christ",
        "level 28: the sewers",
        "level 29: odyssey of noises",
        "level 30: the gateway of hell",

        "level 31: cyberden",
        "level 32: go 2 it",
    },

    mapnamest: [32][:0]const u8 = .{
        // TNT WAD map names.
        "level 1: system control",
        "level 2: human bbq",
        "level 3: power control",
        "level 4: wormhole",
        "level 5: hanger",
        "level 6: open season",
        "level 7: prison",
        "level 8: metal",
        "level 9: stronghold",
        "level 10: redemption",
        "level 11: storage facility",

        "level 12: crater",
        "level 13: nukage processing",
        "level 14: steel works",
        "level 15: dead zone",
        "level 16: deepest reaches",
        "level 17: processing area",
        "level 18: mill",
        "level 19: shipping/respawning",
        "level 20: central processing",

        "level 21: administration center",
        "level 22: habitat",
        "level 23: lunar mining project",
        "level 24: quarry",
        "level 25: baron's den",
        "level 26: ballistyx",
        "level 27: mount pain",
        "level 28: heck",
        "level 29: river styx",
        "level 30: last call",

        "level 31: pharaoh",
        "level 32: caribbean",
    },

    chat_macros: [10][:0]const u8 = .{
        "I'm ready to kick butt!",
        "I'm OK.",
        "I'm not looking too good!",
        "Help!",
        "You suck!",
        "Next time, scumbag...",
        "Come here!",
        "I'll take care of it.",
        "Yes",
        "No",
    },

    HUSTR_TALKTOSELF1: [:0]const u8 = "You mumble to yourself",
    HUSTR_TALKTOSELF2: [:0]const u8 = "Who's there?",
    HUSTR_TALKTOSELF3: [:0]const u8 = "You scare yourself",
    HUSTR_TALKTOSELF4: [:0]const u8 = "You start to rave",
    HUSTR_TALKTOSELF5: [:0]const u8 = "You've lost it...",

    HUSTR_MESSAGESENT: [:0]const u8 = "[Message Sent]",

    player_names: [4][:0]const u8 = .{ "Green: ", "Indigo: ", "Brown: ", "Red: " },
    destination_keys: [4]u8 = .{ 'g', 'i', 'b', 'r' },

    // am_map.zig
    AMSTR_FOLLOWON: [:0]const u8 = "Follow Mode ON",
    AMSTR_FOLLOWOFF: [:0]const u8 = "Follow Mode OFF",

    AMSTR_GRIDON: [:0]const u8 = "Grid ON",
    AMSTR_GRIDOFF: [:0]const u8 = "Grid OFF",

    AMSTR_MARKEDSPOT: [:0]const u8 = "Marked Spot",
    AMSTR_MARKSCLEARED: [:0]const u8 = "All Marks Cleared",

    // st_stuff.zig

    STSTR_MUS: [:0]const u8 = "Music Change",
    STSTR_NOMUS: [:0]const u8 = "IMPOSSIBLE SELECTION",
    STSTR_DQDON: [:0]const u8 = "Degreelessness Mode On",
    STSTR_DQDOFF: [:0]const u8 = "Degreelessness Mode Off",

    STSTR_KFAADDED: [:0]const u8 = "Very Happy Ammo Added",
    STSTR_FAADDED: [:0]const u8 = "Ammo (no keys) Added",

    STSTR_NCON: [:0]const u8 = "No Clipping Mode ON",
    STSTR_NCOFF: [:0]const u8 = "No Clipping Mode OFF",

    STSTR_BEHOLD: [:0]const u8 = "inVuln, Str, Inviso, Rad, Allmap, or Lite-amp",
    STSTR_BEHOLDX: [:0]const u8 = "Power-up Toggled",

    STSTR_CHOPPERS: [:0]const u8 = "... doesn't suck - GM",
    STSTR_CLEV: [:0]const u8 = "Changing Level...",

    // f_finale.zig
    E1TEXT: [:0]const u8 =
        "Once you beat the big badasses and\n" ++
        "clean out the moon base you're supposed\n" ++
        "to win, aren't you? Aren't you? Where's\n" ++
        "your fat reward and ticket home? What\n" ++
        "the hell is this? It's not supposed to\n" ++
        "end this way!\n" ++
        "\n"  ++
        "It stinks like rotten meat, but looks\n" ++
        "like the lost Deimos base.  Looks like\n" ++
        "you're stuck on The Shores of Hell.\n" ++
        "The only way out is through.\n" ++
        "\n" ++
        "To continue the DOOM experience, play\n" ++
        "The Shores of Hell and its amazing\n" ++
        "sequel, Inferno!\n",


    E2TEXT: [:0]const u8 =
        "You've done it! The hideous cyber-\n" ++
        "demon lord that ruled the lost Deimos\n" ++
        "moon base has been slain and you\n" ++
        "are triumphant! But ... where are\n" ++
        "you? You clamber to the edge of the\n" ++
        "moon and look down to see the awful\n" ++
        "truth.\n"  ++
        "\n" ++
        "Deimos floats above Hell itself!\n" ++
        "You've never heard of anyone escaping\n" ++
        "from Hell, but you'll make the bastards\n" ++
        "sorry they ever heard of you! Quickly,\n" ++
        "you rappel down to  the surface of\n" ++
        "Hell.\n" ++
        "\n"  ++
        "Now, it's on to the final chapter of\n" ++
        "DOOM! -- Inferno.",


    E3TEXT: [:0]const u8 =
        "The loathsome spiderdemon that\n" ++
        "masterminded the invasion of the moon\n" ++
        "bases and caused so much death has had\n" ++
        "its ass kicked for all time.\n" ++
        "\n" ++
        "A hidden doorway opens and you enter.\n" ++
        "You've proven too tough for Hell to\n" ++
        "contain, and now Hell at last plays\n" ++
        "fair -- for you emerge from the door\n" ++
        "to see the green fields of Earth!\n" ++
        "Home at last.\n"  ++
        "\n" ++
        "You wonder what's been happening on\n" ++
        "Earth while you were battling evil\n" ++
        "unleashed. It's good that no Hell-\n" ++
        "spawn could have come through that\n" ++
        "door with you ...",


    E4TEXT: [:0]const u8 =
        "the spider mastermind must have sent forth\n" ++
        "its legions of hellspawn before your\n" ++
        "final confrontation with that terrible\n" ++
        "beast from hell.  but you stepped forward\n" ++
        "and brought forth eternal damnation and\n" ++
        "suffering upon the horde as a true hero\n" ++
        "would in the face of something so evil.\n" ++
        "\n" ++
        "besides, someone was gonna pay for what\n" ++
        "happened to daisy, your pet rabbit.\n" ++
        "\n" ++
        "but now, you see spread before you more\n" ++
        "potential pain and gibbitude as a nation\n" ++
        "of demons run amok among our cities.\n" ++
        "\n" ++
        "next stop, hell on earth!",


    // after level 6, put this:

    C1TEXT: [:0]const u8 =
        "YOU HAVE ENTERED DEEPLY INTO THE INFESTED\n"  ++
        "STARPORT. BUT SOMETHING IS WRONG. THE\n"  ++
        "MONSTERS HAVE BROUGHT THEIR OWN REALITY\n"  ++
        "WITH THEM, AND THE STARPORT'S TECHNOLOGY\n"  ++
        "IS BEING SUBVERTED BY THEIR PRESENCE.\n"  ++
        "\n" ++
        "AHEAD, YOU SEE AN OUTPOST OF HELL, A\n"  ++
        "FORTIFIED ZONE. IF YOU CAN GET PAST IT,\n"  ++
        "YOU CAN PENETRATE INTO THE HAUNTED HEART\n"  ++
        "OF THE STARBASE AND FIND THE CONTROLLING\n"  ++
        "SWITCH WHICH HOLDS EARTH'S POPULATION\n"  ++
        "HOSTAGE.",

    // After level 11, put this:

    C2TEXT: [:0]const u8 =
        "YOU HAVE WON! YOUR VICTORY HAS ENABLED\n"  ++
        "HUMANKIND TO EVACUATE EARTH AND ESCAPE\n" ++
        "THE NIGHTMARE.  NOW YOU ARE THE ONLY\n" ++
        "HUMAN LEFT ON THE FACE OF THE PLANET.\n" ++
        "CANNIBAL MUTATIONS, CARNIVOROUS ALIENS,\n" ++
        "AND EVIL SPIRITS ARE YOUR ONLY NEIGHBORS.\n" ++
        "YOU SIT BACK AND WAIT FOR DEATH, CONTENT\n" ++
        "THAT YOU HAVE SAVED YOUR SPECIES.\n" ++
        "\n" ++
        "BUT THEN, EARTH CONTROL BEAMS DOWN A\n" ++
        "MESSAGE FROM SPACE: \"SENSORS HAVE LOCATED\n" ++
        "THE SOURCE OF THE ALIEN INVASION. IF YOU\n" ++
        "GO THERE, YOU MAY BE ABLE TO BLOCK THEIR\n" ++
        "ENTRY.  THE ALIEN BASE IS IN THE HEART OF\n" ++
        "YOUR OWN HOME CITY, NOT FAR FROM THE\n" ++
        "STARPORT.\" SLOWLY AND PAINFULLY YOU GET\n" ++
        "UP AND RETURN TO THE FRAY.",


    // After level 20, put this:

    C3TEXT: [:0]const u8 =
        "YOU ARE AT THE CORRUPT HEART OF THE CITY,\n" ++
        "SURROUNDED BY THE CORPSES OF YOUR ENEMIES.\n" ++
        "YOU SEE NO WAY TO DESTROY THE CREATURES'\n" ++
        "ENTRYWAY ON THIS SIDE, SO YOU CLENCH YOUR\n" ++
        "TEETH AND PLUNGE THROUGH IT.\n" ++
        "\n" ++
        "THERE MUST BE A WAY TO CLOSE IT ON THE\n" ++
        "OTHER SIDE. WHAT DO YOU CARE IF YOU'VE\n" ++
        "GOT TO GO THROUGH HELL TO GET TO IT?",


    // After level 29, put this:

    C4TEXT: [:0]const u8 =
        "THE HORRENDOUS VISAGE OF THE BIGGEST\n" ++
        "DEMON YOU'VE EVER SEEN CRUMBLES BEFORE\n" ++
        "YOU, AFTER YOU PUMP YOUR ROCKETS INTO\n" ++
        "HIS EXPOSED BRAIN. THE MONSTER SHRIVELS\n" ++
        "UP AND DIES, ITS THRASHING LIMBS\n" ++
        "DEVASTATING UNTOLD MILES OF HELL'S\n" ++
        "SURFACE.\n" ++
        "\n" ++
        "YOU'VE DONE IT. THE INVASION IS OVER.\n" ++
        "EARTH IS SAVED. HELL IS A WRECK. YOU\n" ++
        "WONDER WHERE BAD FOLKS WILL GO WHEN THEY\n" ++
        "DIE, NOW. WIPING THE SWEAT FROM YOUR\n" ++
        "FOREHEAD YOU BEGIN THE LONG TREK BACK\n" ++
        "HOME. REBUILDING EARTH OUGHT TO BE A\n" ++
        "LOT MORE FUN THAN RUINING IT WAS.\n",



    // Before level 31, put this:

    C5TEXT: [:0]const u8 =
        "CONGRATULATIONS, YOU'VE FOUND THE SECRET\n" ++
        "LEVEL! LOOKS LIKE IT'S BEEN BUILT BY\n" ++
        "HUMANS, RATHER THAN DEMONS. YOU WONDER\n" ++
        "WHO THE INMATES OF THIS CORNER OF HELL\n" ++
        "WILL BE.",


    // Before level 32, put this:

    C6TEXT: [:0]const u8 =
        "CONGRATULATIONS, YOU'VE FOUND THE\n" ++
        "SUPER SECRET LEVEL!  YOU'D BETTER\n" ++
        "BLAZE THROUGH THIS ONE!\n",


    // after map 06

    P1TEXT: [:0]const u8 =
        "You gloat over the steaming carcass of the\n" ++
        "Guardian.  With its death, you've wrested\n" ++
        "the Accelerator from the stinking claws\n" ++
        "of Hell.  You relax and glance around the\n" ++
        "room.  Damn!  There was supposed to be at\n" ++
        "least one working prototype, but you can't\n" ++
        "see it. The demons must have taken it.\n" ++
        "\n" ++
        "You must find the prototype, or all your\n" ++
        "struggles will have been wasted. Keep\n" ++
        "moving, keep fighting, keep killing.\n" ++
        "Oh yes, keep living, too.",


    // after map 11

    P2TEXT: [:0]const u8 =
        "Even the deadly Arch-Vile labyrinth could\n" ++
        "not stop you, and you've gotten to the\n" ++
        "prototype Accelerator which is soon\n" ++
        "efficiently and permanently deactivated.\n" ++
        "\n" ++
        "You're good at that kind of thing.",


    // after map 20

    P3TEXT: [:0]const u8 =
        "You've bashed and battered your way into\n" ++
        "the heart of the devil-hive.  Time for a\n" ++
        "Search-and-Destroy mission, aimed at the\n" ++
        "Gatekeeper, whose foul offspring is\n" ++
        "cascading to Earth.  Yeah, he's bad. But\n" ++
        "you know who's worse!\n" ++
        "\n" ++
        "Grinning evilly, you check your gear, and\n" ++
        "get ready to give the bastard a little Hell\n" ++
        "of your own making!",

    // after map 30

    P4TEXT: [:0]const u8 =
        "The Gatekeeper's evil face is splattered\n" ++
        "all over the place.  As its tattered corpse\n" ++
        "collapses, an inverted Gate forms and\n" ++
        "sucks down the shards of the last\n" ++
        "prototype Accelerator, not to mention the\n" ++
        "few remaining demons.  You're done. Hell\n" ++
        "has gone back to pounding bad dead folks \n" ++
        "instead of good live ones.  Remember to\n" ++
        "tell your grandkids to put a rocket\n" ++
        "launcher in your coffin. If you go to Hell\n" ++
        "when you die, you'll need it for some\n" ++
        "final cleaning-up ...",

    // before map 31

    P5TEXT: [:0]const u8 =
        "You've found the second-hardest level we\n" ++
        "got. Hope you have a saved game a level or\n" ++
        "two previous.  If not, be prepared to die\n" ++
        "aplenty. For master marines only.",

    // before map 32

    P6TEXT: [:0]const u8 =
        "Betcha wondered just what WAS the hardest\n" ++
        "level we had ready for ya?  Now you know.\n" ++
        "No one gets out alive.",


    T1TEXT: [:0]const u8 =
        "You've fought your way out of the infested\n" ++
        "experimental labs.   It seems that UAC has\n" ++
        "once again gulped it down.  With their\n" ++
        "high turnover, it must be hard for poor\n" ++
        "old UAC to buy corporate health insurance\n" ++
        "nowadays..\n" ++
        "\n" ++
        "Ahead lies the military complex, now\n" ++
        "swarming with diseased horrors hot to get\n" ++
        "their teeth into you. With luck, the\n" ++
        "complex still has some warlike ordnance\n" ++
        "laying around.",


    T2TEXT: [:0]const u8 =
        "You hear the grinding of heavy machinery\n" ++
        "ahead.  You sure hope they're not stamping\n" ++
        "out new hellspawn, but you're ready to\n" ++
        "ream out a whole herd if you have to.\n" ++
        "They might be planning a blood feast, but\n" ++
        "you feel about as mean as two thousand\n" ++
        "maniacs packed into one mad killer.\n" ++
        "\n" ++
        "You don't plan to go down easy.",


    T3TEXT: [:0]const u8 =
        "The vista opening ahead looks real damn\n" ++
        "familiar. Smells familiar, too -- like\n" ++
        "fried excrement. You didn't like this\n" ++
        "place before, and you sure as hell ain't\n" ++
        "planning to like it now. The more you\n" ++
        "brood on it, the madder you get.\n" ++
        "Hefting your gun, an evil grin trickles\n" ++
        "onto your face. Time to take some names.",

    T4TEXT: [:0]const u8 =
        "Suddenly, all is silent, from one horizon\n" ++
        "to the other. The agonizing echo of Hell\n" ++
        "fades away, the nightmare sky turns to\n" ++
        "blue, the heaps of monster corpses start \n" ++
        "to evaporate along with the evil stench \n" ++
        "that filled the air. Jeeze, maybe you've\n" ++
        "done it. Have you really won?\n" ++
        "\n" ++
        "Something rumbles in the distance.\n" ++
        "A blue light begins to glow inside the\n" ++
        "ruined skull of the demon-spitter.",


    T5TEXT: [:0]const u8 =
        "What now? Looks totally different. Kind\n" ++
        "of like King Tut's condo. Well,\n" ++
        "whatever's here can't be any worse\n" ++
        "than usual. Can it?  Or maybe it's best\n" ++
        "to let sleeping gods lie..",


    T6TEXT: [:0]const u8 =
        "Time for a vacation. You've burst the\n" ++
        "bowels of hell and by golly you're ready\n" ++
        "for a break. You mutter to yourself,\n" ++
        "Maybe someone else can kick Hell's ass\n" ++
        "next time around. Ahead lies a quiet town,\n" ++
        "with peaceful flowing water, quaint\n" ++
        "buildings, and presumably no Hellspawn.\n" ++
        "\n" ++
        "As you step off the transport, you hear\n" ++
        "the stomp of a cyberdemon's iron shoe.",

    // Character cast strings f_finale.zig
    CC_ZOMBIE: [:0]const u8 = "ZOMBIEMAN",
    CC_SHOTGUN: [:0]const u8 = "SHOTGUN GUY",
    CC_HEAVY: [:0]const u8 = "HEAVY WEAPON DUDE",
    CC_IMP: [:0]const u8 = "IMP",
    CC_DEMON: [:0]const u8 = "DEMON",
    CC_LOST: [:0]const u8 = "LOST SOUL",
    CC_CACO: [:0]const u8 = "CACODEMON",
    CC_HELL: [:0]const u8 = "HELL KNIGHT",
    CC_BARON: [:0]const u8 = "BARON OF HELL",
    CC_ARACH: [:0]const u8 = "ARACHNOTRON",
    CC_PAIN: [:0]const u8 = "PAIN ELEMENTAL",
    CC_REVEN: [:0]const u8 = "REVENANT",
    CC_MANCU: [:0]const u8 = "MANCUBUS",
    CC_ARCH: [:0]const u8 = "ARCH-VILE",
    CC_SPIDER: [:0]const u8 = "THE SPIDER MASTERMIND",
    CC_CYBER: [:0]const u8 = "THE CYBERDEMON",
    CC_HERO: [:0]const u8 = "OUR HERO",
};
