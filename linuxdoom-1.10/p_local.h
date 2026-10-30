// Emacs style mode select   -*- C++ -*- 
//-----------------------------------------------------------------------------
//
// $Id:$
//
// Copyright (C) 1993-1996 by id Software, Inc.
//
// This source is available for distribution and/or modification
// only under the terms of the DOOM Source Code License as
// published by id Software. All rights reserved.
//
// The source is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// FITNESS FOR A PARTICULAR PURPOSE. See the DOOM Source Code License
// for more details.
//
// DESCRIPTION:
//	Play functions, animation, global header.
//
//-----------------------------------------------------------------------------


#ifndef __P_LOCAL__
#define __P_LOCAL__

#ifndef __R_LOCAL__
#include "r_local.h"
#endif

#define FLOATSPEED		(FRACUNIT*4)


#define MAXHEALTH		100
#define VIEWHEIGHT		(41*FRACUNIT)

// mapblocks are used to check movement
// against lines and things
#define MAPBLOCKUNITS	128
#define MAPBLOCKSIZE	(MAPBLOCKUNITS*FRACUNIT)
#define MAPBLOCKSHIFT	(FRACBITS+7)
#define MAPBMASK		(MAPBLOCKSIZE-1)
#define MAPBTOFRAC		(MAPBLOCKSHIFT-FRACBITS)


// player radius for movement checking
#define PLAYERRADIUS	16*FRACUNIT

// MAXRADIUS is for precalculated sector block boxes
// the spider demon is larger,
// but we do not have any moving sectors nearby
#define MAXRADIUS		32*FRACUNIT

#define GRAVITY		FRACUNIT
#define MAXMOVE		(30*FRACUNIT)

#define USERANGE		(64*FRACUNIT)
#define MELEERANGE		(64*FRACUNIT)
#define MISSILERANGE	(32*64*FRACUNIT)

// follow a player exlusively for 3 seconds
#define	BASETHRESHOLD	 	100



//
// P_TICK
//

// both the head and tail of the thinker list
extern	thinker_t	thinkercap;	


void P_InitThinkers (void);
void P_AddThinker (thinker_t* thinker);
void P_RemoveThinker (thinker_t* thinker);


//
// P_MOBJ
//
#define ONFLOORZ		MININT
#define ONCEILINGZ		MAXINT

// Time interval for item respawning.
#define ITEMQUESIZE		128



void 	P_RemoveMobj (mobj_t* th);
void 	P_MobjThinker (mobj_t* mobj);


//
// P_MAPUTL
//
typedef struct
{
    fixed_t	x;
    fixed_t	y;
    fixed_t	dx;
    fixed_t	dy;
    
} divline_t;

typedef struct
{
    fixed_t	frac;		// along trace line
    boolean	isaline;
    union {
	mobj_t*	thing;
	line_t*	line;
    }			d;
} intercept_t;

#define PT_ADDLINES		1
#define PT_ADDTHINGS	2
#define PT_EARLYOUT		4

void P_SetThingPosition (mobj_t* thing);


//
// P_MAP
//


boolean P_ChangeSector (sector_t* sector, boolean crunch);



//
// P_INTER
//
extern int		maxammo[NUMAMMO];
extern int		clipammo[NUMAMMO];

void
P_DamageMobj
( mobj_t*	target,
  mobj_t*	inflictor,
  mobj_t*	source,
  int		damage );


//
// P_SPEC
//
#include "p_spec.h"


#endif	// __P_LOCAL__
//-----------------------------------------------------------------------------
//
// $Log:$
//
//-----------------------------------------------------------------------------


