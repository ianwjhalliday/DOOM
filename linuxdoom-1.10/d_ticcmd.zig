// The data sampled per tick (single player)
// and transmitted to other peers (multiplayer).
// Mainly movements/button commands per game tick,
// plus a checksum for internal state consistency.
pub const TicCmd = extern struct {
    forwardmove: i8,        // *2048 for move
    sidemove: i8,           // *2048 for move
    angleturn: c_short,     // <<16 for angle delta
    consistancy: c_short,   // checks for net game
    chatchar: u8,
    buttons: u8,
};
