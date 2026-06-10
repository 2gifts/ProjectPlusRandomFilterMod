################################################################################
# Per-Port Random Subset v1.0.0
#
# Each controller port builds its own random-character LIST on the CSS:
#   * Hover a character tile and TAP L  -> add/remove it from YOUR list
#     (menu SFX confirms: "enter" = added, "exit" = removed)
#   * Hover the RANDOM tile and TAP L   -> clear YOUR list (back to everyone)
#   * Drop your coin on RANDOM          -> a character is rolled from your list
#     right then (empty list = full roster, vanilla behavior); pick the coin
#     back up and re-drop to re-roll
#
# Lists live in scratch RAM (persist across matches, reset on power off).
# Replaces "[Legacy TE] Melee Random v2" (vestigial in P+; removed from the
# codeset).
#
# Targets Project+ (RSBE01). Key facts (verified live against P+ 3.1.5):
#   - sora_menu_sel_char.rel loads at 0x80682800
#   - random pool table: 42 slot IDs at 0x80680E80, count = imm at 0x806857F2
#   - CSS per-port player object pointers at 0x805882E0; player object:
#     +0x1B0 = port, +0x1B8 = hovered slot, +0x1A8 -> hand, hand+0xA0 = coin
#   - per-port input proc 0x806898C0(this, idx): r25 = port, r26 = player obj
#   - random drop handler: 0x8068B814 'li r4, 0x29' -> setSlot(player, 0x29);
#     r30 = player object. We roll there instead (fresh at drop time).
#   - muSelCharTask::initPlayerArea rolls a default char per port at CSS entry
#     (r25 = port, patch site 0x80685824); the match consumes that value when
#     a port is still on raw random, so it must be pool-aware too.
#   - scratch 0x80002840+ is unclaimed (MusicSelect ends at 0x8000283C)
.alias MagicAddr     = 0x80002840   # 'RSUB' once pools are initialized
.alias MagicVal      = 0x52535542
.alias PoolBase      = 0x80002848   # 4 ports x PoolStride bytes, 1 byte per
.alias PoolStride    = 0x30         #   random-table index (1 = on my list)
.alias PoolTotal     = 0xC0


.alias RandTable     = 0x80680E80   # P+ CSS Random Data (42 slot IDs)
.alias RandCountAddr = 0x806857F2   # low half of 'li r23, 42'

.alias randi               = 0x8003FC7C
.alias g_gfPadSystem       = 0x805A0040
.alias playSE              = 0x800742B0   # (sndSystem*, id, -1, 0, 0, -1)
.alias g_sndSystem         = 0x805A01D0
.alias exchangeCharKind    = 0x806948D4   # (player*, slotKind) -> kind
.alias initCharKind        = 0x80693D18   # (player*, kind)
.alias getNumCharColor     = 0x800AF8D0   # (slotKind) -> costume count
.alias setCharPic          = 0x8069742C
.alias updateCharFace      = 0x800AF82C
.alias getCharFaceParam    = 0x800AF6F0
.alias setFranchiseIcon    = 0x800B7900   # (obj+0xB8 thing, f1)
.alias setStockCharKind    = 0x80692498
.alias PrevPadBase         = 0x80002920   # 4 words: per-port previous buttons
.alias DropChoice          = 0x80002930   # slot chosen by the drop-time roll
.alias PreRollOff          = 0x410        # player object: deferred-random char

.alias ToggleButton  = 0x0040       # L: list add/remove + clear (on '?')
.alias InstantButton = 0x0010       # Z: held during a '?' drop = instant roll
# getSysPadStatus output: shipped P+ code (Random.asm RSS) reads buttons at buf+4
.alias SFX_On        = 0x26         # menu "enter"
.alias SFX_Off       = 0x28         # menu "exit"
.alias SFX_Reset     = 0x25         # menu "enter 3"

.macro lwi(<reg>, <val>)
{
    .alias  temp_Hi = <val> / 0x10000
    .alias  temp_Lo = <val> & 0xFFFF
    lis     <reg>, temp_Hi
    ori     <reg>, <reg>, temp_Lo
}
.macro lwd(<reg>, <addr>)
{
    .alias  temp_Lo = <addr> & 0xFFFF
    .alias  temp_Hi_ = <addr> / 0x10000
    .alias  temp_r = temp_Lo / 0x8000
    .alias  temp_Hi = temp_Hi_ + temp_r
    lis     <reg>, temp_Hi
    lwz     <reg>, temp_Lo(<reg>)
}
.macro call(<addr>)
{
    %lwi(r12, <addr>)
    mtctr r12
    bctrl
}

################################################################
# Hook 1: pool toggle. Hooks the per-port CSS input processor
# 0x806898C0(this, idx) early, where r24 = manager (static at
# 0x8058829C; per-port player objects at +0x44 = 0x805882E0),
# r25 = port index, r26 = player object (+0x1B0 port, +0x1B8
# hovered slot). Replaced instruction: lwz r0, 0(r26).
#
# UX: hover any character tile and TAP L -> toggle it in/out of
# your pool. Tap L on the RANDOM tile -> reset your pool.
# Edge detection via per-port previous-buttons words.
################################################################
HOOK @ $806898E8
{
    stwu r1, -0xB0(r1)
    mflr r0
    stw r0, 0xB4(r1)
    stw r3, 0x28(r1)
    stw r4, 0x2C(r1)
    stw r5, 0x30(r1)
    stw r6, 0x34(r1)

    cmplwi r25, 3
    bgt- TogOut

    # one-time pool init (all characters enabled)
    %lwi(r11, MagicAddr)
    lwz r12, 0(r11)
    %lwi(r10, MagicVal)
    cmpw r12, r10
    beq+ TogInited
    stw r10, 0(r11)
    %lwi(r9, PoolBase)
    li r8, PoolTotal
    li r7, 0                     # empty list = no restriction
TogInitLoop:
    subic. r8, r8, 1
    stbx r7, r9, r8
    bne+ TogInitLoop
    %lwi(r9, PrevPadBase)        # also clear the edge-detector state
    li r8, 0
    stw r8, 0x0(r9)
    stw r8, 0x4(r9)
    stw r8, 0x8(r9)
    stw r8, 0xC(r9)
TogInited:

    # buttons for this port: read the live held words at
    # gfPadSystem + 0x40 + port*0x40 (verified empirically). Do NOT call
    # getSysPadStatus here -- it consumes press edges the game needs.
    %lwd(r12, g_gfPadSystem)
    addi r11, r25, 1
    slwi r11, r11, 6
    lwzx r12, r12, r11
    %lwi(r9, PrevPadBase)
    slwi r10, r25, 2
    lwzx r11, r9, r10            # previous buttons
    stwx r12, r9, r10
    andc r12, r12, r11           # newly pressed this frame
    andi. r0, r12, ToggleButton
    beq+ TogOut

    lwz r5, 0x1B8(r26)           # hovered slot: the '?' tile reads 0x29
    cmpwi r5, 0x29               #   (0x28 is the empty-space default)
    bne- TogFindChar
    lwz r9, 0x1A8(r26)           # coin in hand (not yet placed)?
    lwz r9, 0xA0(r9)
    cmpwi r9, 0
    beq- TogOut                  # already placed on random: ignore L
    b TogReset                   # hovering '?' with the coin: clear the list
TogFindChar:

    # slot id -> random-table index
    %lwi(r6, RandTable)
    %lwi(r7, RandCountAddr)
    lhz r7, 0(r7)
    li r8, 0
TogFind:
    lbzx r9, r6, r8
    cmpw r9, r5
    beq- TogFound
    addi r8, r8, 1
    cmpw r8, r7
    blt+ TogFind
    b TogOut                     # not in the random table: ignore
TogFound:
    mulli r9, r25, PoolStride
    %lwi(r10, PoolBase)
    add r9, r9, r10
    lbzx r11, r9, r8
    xori r11, r11, 1
    andi. r11, r11, 1
    stbx r11, r9, r8
    li r4, SFX_Off
    beq- TogReroll
    li r4, SFX_On
    b TogReroll

TogReset:
    mulli r9, r25, PoolStride
    %lwi(r10, PoolBase)
    add r9, r9, r10
    li r8, PoolStride
    li r7, 0                     # clear the list
TogResetLoop:
    subic. r8, r8, 1
    stbx r7, r9, r8
    bne+ TogResetLoop
    li r4, SFX_Reset

TogReroll:
    # refresh this port's deferred-random character (obj+0x410) from the
    # new list, so a coin sitting on the '?' slot stays fresh
    stw r4, 0x48(r1)             # keep the SFX id across calls
    mulli r9, r25, PoolStride
    %lwi(r10, PoolBase)
    add r9, r9, r10
    %lwi(r7, RandCountAddr)
    lhz r7, 0(r7)
    li r8, 0
    li r6, 0
RerollCount:
    cmpw r6, r7
    bge- RerollCounted
    lbzx r11, r9, r6
    andi. r11, r11, 1
    add r8, r8, r11
    addi r6, r6, 1
    b RerollCount
RerollCounted:
    li r12, 0
    cmpwi r8, 0
    bne- RerollHave
    li r12, 1                    # empty list: roll over everyone
    mr r8, r7
RerollHave:
    stw r9, 0x38(r1)
    stw r7, 0x3C(r1)
    stw r12, 0x40(r1)
    mr r3, r8
    %call(randi)
    lwz r9, 0x38(r1)
    lwz r7, 0x3C(r1)
    lwz r12, 0x40(r1)
    li r6, 0
RerollWalk:
    cmpwi r12, 0
    bne- RerollHit
    lbzx r11, r9, r6
    andi. r11, r11, 1
    beq- RerollNext
RerollHit:
    cmpwi r3, 0
    beq- RerollChosen
    subi r3, r3, 1
RerollNext:
    addi r6, r6, 1
    cmpw r6, r7
    blt+ RerollWalk
    li r6, 0
RerollChosen:
    %lwi(r9, RandTable)
    lbzx r9, r9, r6
    stw r9, PreRollOff(r26)      # the match reads this when slot is raw random
    lwz r4, 0x48(r1)

TogSfx:
    %lwd(r3, g_sndSystem)
    li r5, -1
    li r6, 0
    li r7, 0
    li r8, -1
    %call(playSE)
    b TogOut

TogOut:
    lwz r3, 0x28(r1)
    lwz r4, 0x2C(r1)
    lwz r5, 0x30(r1)
    lwz r6, 0x34(r1)
    lwz r0, 0xB4(r1)
    mtlr r0
    addi r1, r1, 0xB0
    lwz r0, 0(r26)               # original instruction
}

################################################################
# Hook 2: per-port random roll. Replaces Melee Random v2.
# At 0x8068AE24 (original op: mr r3, r29): r27 = slot kind being
# placed (0x28 = Random), r28 = player object, r31 = manager.
# The vanilla "skip if random" beq at 0x8068AE20 stays NOPed.
################################################################
op nop @ $8068AE20

HOOK @ $8068AE24
{
    cmpwi r27, 0x28
    bne- TheEnd
    stwu r1, -0x40(r1)
    mflr r0
    stw r0, 0x44(r1)

    # one-time pool init (all characters enabled)
    %lwi(r11, MagicAddr)
    lwz r12, 0(r11)
    %lwi(r10, MagicVal)
    cmpw r12, r10
    beq+ RollInited
    stw r10, 0(r11)
    %lwi(r9, PoolBase)
    li r8, PoolTotal
    li r7, 0                     # empty list = no restriction
RollInitLoop:
    subic. r8, r8, 1
    stbx r7, r9, r8
    bne+ RollInitLoop
RollInited:

    # which port is rolling? (player object stores it at +0x1B0)
    lwz r5, 0x1B0(r28)
    cmplwi r5, 3
    ble+ RollPortOk
    li r5, 0                     # out of range: behave like P1
RollPortOk:
    mulli r6, r5, PoolStride
    %lwi(r7, PoolBase)
    add r7, r7, r6
    stw r7, 0x28(r1)             # pool for this port

    %lwi(r8, RandCountAddr)
    lhz r8, 0(r8)
    stw r8, 0x2C(r1)             # table size

    # count enabled entries
    li r9, 0
    li r10, 0
RollCountLoop:
    cmpw r10, r8
    bge- RollCountDone
    lbzx r11, r7, r10
    andi. r11, r11, 1
    add r9, r9, r11
    addi r10, r10, 1
    b RollCountLoop
RollCountDone:
    li r12, 0
    cmpwi r9, 0
    bne- RollHavePool
    li r12, 1                    # empty pool: fall back to everyone
    mr r9, r8
RollHavePool:
    stw r12, 0x30(r1)

    mr r3, r9
    %call(randi)                 # r3 = 0 .. enabled-1

    # walk to the r3-th enabled table index
    lwz r7, 0x28(r1)
    lwz r8, 0x2C(r1)
    lwz r12, 0x30(r1)
    li r10, 0
RollWalk:
    cmpwi r12, 0
    bne- RollHit
    lbzx r11, r7, r10
    andi. r11, r11, 1
    beq- RollNext
RollHit:
    cmpwi r3, 0
    beq- RollChosen
    subi r3, r3, 1
RollNext:
    addi r10, r10, 1
    cmpw r10, r8
    blt+ RollWalk
    li r10, 0
RollChosen:
    %lwi(r6, RandTable)
    lbzx r4, r6, r10             # chosen character slot id

    # ---- apply pick: mirrors Melee Random v2's update sequence ----
    mr r3, r28
    %call(exchangeCharKind)
    mr r4, r3
    mr r3, r28
    %call(initCharKind)

    lwz r3, 0x1B8(r28)
    %call(getNumCharColor)
    cmpwi r3, 1
    ble- RollCostumeZero
    %call(randi)
    b RollCostumeStore
RollCostumeZero:
    li r3, 0
RollCostumeStore:
    stw r3, 0x1BC(r28)

    mr r3, r28
    lwz r4, 0x1B8(r28)
    lwz r5, 0x1B4(r28)
    lwz r6, 0x1BC(r28)
    lwz r7, 0x1F4(r28)
    lbz r7, 0x5C8(r7)
    lwz r8, 0x1C0(r28)
    lbz r9, 0x1C4(r28)
    %call(setCharPic)

    lwz r3, 0x1B8(r28)
    %call(updateCharFace)
    %call(getCharFaceParam)
    addi r3, r3, 1
    # int -> float in f1, minus module constant (as Melee Random's helper)
    xoris r3, r3, 0x8000
    stw r3, 0x3C(r1)
    lis r0, 0x4330
    stw r0, 0x38(r1)
    lfd f0, 0x38(r1)
    lis r12, 0x806A
    lfd f1, 0x0EB8(r12)
    fsubs f1, f0, f1
    lwz r3, 0xB8(r28)
    %call(setFranchiseIcon)

    lwz r0, 0x3DC(r31)
    lwz r27, 0x1B8(r28)          # code after the hook expects the new slot here
    cmpwi r0, 0
    beq- RollDone
    mr r3, r31
    lwz r4, 0x1B8(r28)
    lwz r5, 0x1BC(r28)
    %call(setStockCharKind)
RollDone:
    lwz r0, 0x44(r1)
    mtlr r0
    addi r1, r1, 0x40
TheEnd:
    mr r3, r29
}

################################################################
# Hook 3: per-port roll at MATCH START (the path that resolves a
# coin still sitting on Random when the game begins).
# At 0x80685824: r25 = port, r23 = pool count (li r23,42 patch at
# 0x806857F0), r0 = vanilla rolled index, r4 LIVE (do not clobber).
# Original op "lis r3, 0x8068" is the last body instruction; the
# two instructions after the hook do char = byte[0x80680E80 + r0],
# so we only need to leave our chosen index in r0.
################################################################
HOOK @ $80685824
{
    stwu r1, -0x40(r1)
    mflr r0
    stw r0, 0x44(r1)
    stw r4, 0x28(r1)

    # one-time pool init (all characters enabled)
    %lwi(r11, MagicAddr)
    lwz r12, 0(r11)
    %lwi(r10, MagicVal)
    cmpw r12, r10
    beq+ StartInited
    stw r10, 0(r11)
    %lwi(r9, PoolBase)
    li r8, PoolTotal
    li r7, 0                     # empty list = no restriction
StartInitLoop:
    subic. r8, r8, 1
    stbx r7, r9, r8
    bne+ StartInitLoop
StartInited:

    mr r5, r25                   # port
    cmplwi r5, 3
    ble+ StartPortOk
    li r5, 0
StartPortOk:
    mulli r6, r5, PoolStride
    %lwi(r7, PoolBase)
    add r7, r7, r6
    mr r8, r23                   # table size

    li r9, 0
    li r10, 0
StartCountLoop:
    cmpw r10, r8
    bge- StartCountDone
    lbzx r11, r7, r10
    andi. r11, r11, 1
    add r9, r9, r11
    addi r10, r10, 1
    b StartCountLoop
StartCountDone:
    li r12, 0
    cmpwi r9, 0
    bne- StartHavePool
    li r12, 1                    # empty pool: everyone
    mr r9, r8
StartHavePool:
    stw r7, 0x2C(r1)
    stw r8, 0x30(r1)
    stw r12, 0x34(r1)

    mr r3, r9
    %call(randi)                 # r3 = 0 .. enabled-1

    lwz r7, 0x2C(r1)
    lwz r8, 0x30(r1)
    lwz r12, 0x34(r1)
    li r10, 0
StartWalk:
    cmpwi r12, 0
    bne- StartHit
    lbzx r11, r7, r10
    andi. r11, r11, 1
    beq- StartNext
StartHit:
    cmpwi r3, 0
    beq- StartChosen
    subi r3, r3, 1
StartNext:
    addi r10, r10, 1
    cmpw r10, r8
    blt+ StartWalk
    li r10, 0
StartChosen:
    lwz r4, 0x28(r1)
    lwz r11, 0x44(r1)
    mtlr r11
    addi r1, r1, 0x40
    mr r0, r10                   # our index; consumed by the add after the hook
    lis r3, 0x8068               # original instruction
}

################################################################
# Hook 4: drop-time roll. The random drop handler does
#   0x8068B814  mr r3, r30        (r30 = player object)
#   0x8068B818  li r4, 0x29       <- replaced: roll from the list NOW
#   0x8068B81C  bl setSlot
#   ...
#   0x8068B828  li r5, 0x29       <- replaced: same chosen slot (panel state)
# Non-empty list: place the rolled character itself (fresh roll every
# drop; pick up and re-drop to re-roll). Empty list: keep vanilla 0x29
# (deferred random over the full roster).
################################################################
HOOK @ $8068B818
{
    stwu r1, -0x40(r1)
    mflr r0
    stw r0, 0x44(r1)
    stw r3, 0x28(r1)             # r3 already holds the setSlot 'this' arg

    # one-time list init (empty)
    %lwi(r11, MagicAddr)
    lwz r12, 0(r11)
    %lwi(r10, MagicVal)
    cmpw r12, r10
    beq+ DropInited
    stw r10, 0(r11)
    %lwi(r9, PoolBase)
    li r8, PoolTotal
    li r7, 0
DropInitLoop:
    subic. r8, r8, 1
    stbx r7, r9, r8
    bne+ DropInitLoop
DropInited:

    lwz r4, 0x1B0(r30)           # port
    cmplwi r4, 3
    bgt- DropVanilla

    # Melee-style instant roll only while L is held during the drop;
    # otherwise the '?' placement stays a mystery (deferred random)
    %lwd(r12, g_gfPadSystem)
    addi r11, r4, 1
    slwi r11, r11, 6
    lwzx r12, r12, r11
    andi. r0, r12, InstantButton
    beq- DropMystery

    mulli r5, r4, PoolStride
    %lwi(r6, PoolBase)
    add r6, r6, r5               # this port's list
    %lwi(r7, RandCountAddr)
    lhz r7, 0(r7)                # table size

    li r8, 0                     # listed count
    li r9, 0
DropCount:
    cmpw r9, r7
    bge- DropCounted
    lbzx r10, r6, r9
    andi. r10, r10, 1
    add r8, r8, r10
    addi r9, r9, 1
    b DropCount
DropCounted:
    cmpwi r8, 0
    beq- DropVanilla             # empty list: vanilla deferred random

    stw r6, 0x2C(r1)
    stw r7, 0x30(r1)
    mr r3, r8
    %call(randi)                 # r3 = 0 .. listed-1
    lwz r6, 0x2C(r1)
    lwz r7, 0x30(r1)
    li r9, 0
DropWalk:
    lbzx r10, r6, r9
    andi. r10, r10, 1
    beq- DropNext
    cmpwi r3, 0
    beq- DropChosen
    subi r3, r3, 1
DropNext:
    addi r9, r9, 1
    cmpw r9, r7
    blt+ DropWalk
    li r9, 0
DropChosen:
    %lwi(r6, RandTable)
    lbzx r4, r6, r9              # the rolled character's slot id
    b DropDone

DropMystery:
    # deferred random: refresh this port's hidden pre-roll (obj+0x410) from
    # the current list so the match rolls fresh; empty list keeps the
    # CSS-entry roll (full roster)
    mulli r5, r4, PoolStride
    %lwi(r6, PoolBase)
    add r6, r6, r5
    %lwi(r7, RandCountAddr)
    lhz r7, 0(r7)
    li r8, 0
    li r9, 0
MystCount:
    cmpw r9, r7
    bge- MystCounted
    lbzx r10, r6, r9
    andi. r10, r10, 1
    add r8, r8, r10
    addi r9, r9, 1
    b MystCount
MystCounted:
    cmpwi r8, 0
    beq- DropVanilla             # empty list: leave the entry roll alone
    stw r6, 0x2C(r1)
    stw r7, 0x30(r1)
    mr r3, r8
    %call(randi)
    lwz r6, 0x2C(r1)
    lwz r7, 0x30(r1)
    li r9, 0
MystWalk:
    lbzx r10, r6, r9
    andi. r10, r10, 1
    beq- MystNext
    cmpwi r3, 0
    beq- MystChosen
    subi r3, r3, 1
MystNext:
    addi r9, r9, 1
    cmpw r9, r7
    blt+ MystWalk
    li r9, 0
MystChosen:
    %lwi(r6, RandTable)
    lbzx r6, r6, r9
    stw r6, PreRollOff(r30)      # hidden until the match loads
    b DropVanilla

DropVanilla:
    li r4, 0x29
DropDone:
    %lwi(r11, DropChoice)
    stw r4, 0(r11)
    lwz r3, 0x28(r1)
    lwz r0, 0x44(r1)
    mtlr r0
    addi r1, r1, 0x40
}

HOOK @ $8068B828
{
    %lwi(r5, DropChoice)         # the slot chosen in the B818 hook
    lwz r5, 0(r5)
}

################################################################
# Hooks 5+6: the second random-drop block (other UI flow):
#   0x806892B0  lwz r26, 0x1B8(r3)   (r3 = player obj via r27+0x14)
#   0x806892B4  cmpwi r26, 0x28
#   0x806892BC  mr r3, r28
#   0x806892C4  li r26, 0x29   <- replaced (the new slot value)
#   0x806892C8  li r5, 0x29    <- replaced (panel-state arg)
# Same behavior as hooks at B818/B828: L held = instant roll,
# plain drop = mystery (0x29) with a fresh hidden pre-roll.
################################################################
HOOK @ $806892C4
{
    stwu r1, -0x40(r1)
    mflr r0
    stw r0, 0x44(r1)
    stw r3, 0x28(r1)
    stw r4, 0x2C(r1)

    lwz r26, 0x14(r27)           # player object
    lwz r4, 0x1B0(r26)           # port
    cmplwi r4, 3
    bgt- Drop2Vanilla

    %lwd(r12, g_gfPadSystem)
    addi r11, r4, 1
    slwi r11, r11, 6
    lwzx r12, r12, r11
    andi. r0, r12, InstantButton
    beq- Drop2Mystery

    mulli r5, r4, PoolStride
    %lwi(r6, PoolBase)
    add r6, r6, r5
    %lwi(r7, RandCountAddr)
    lhz r7, 0(r7)
    li r8, 0
    li r9, 0
Drop2Count:
    cmpw r9, r7
    bge- Drop2Counted
    lbzx r10, r6, r9
    andi. r10, r10, 1
    add r8, r8, r10
    addi r9, r9, 1
    b Drop2Count
Drop2Counted:
    cmpwi r8, 0
    beq- Drop2Vanilla
    stw r6, 0x30(r1)
    stw r7, 0x34(r1)
    mr r3, r8
    %call(randi)
    lwz r6, 0x30(r1)
    lwz r7, 0x34(r1)
    li r9, 0
Drop2Walk:
    lbzx r10, r6, r9
    andi. r10, r10, 1
    beq- Drop2Next
    cmpwi r3, 0
    beq- Drop2Chosen
    subi r3, r3, 1
Drop2Next:
    addi r9, r9, 1
    cmpw r9, r7
    blt+ Drop2Walk
    li r9, 0
Drop2Chosen:
    %lwi(r6, RandTable)
    lbzx r26, r6, r9             # instant: place the rolled character
    b Drop2Done

Drop2Mystery:
    mulli r5, r4, PoolStride
    %lwi(r6, PoolBase)
    add r6, r6, r5
    %lwi(r7, RandCountAddr)
    lhz r7, 0(r7)
    li r8, 0
    li r9, 0
Myst2Count:
    cmpw r9, r7
    bge- Myst2Counted
    lbzx r10, r6, r9
    andi. r10, r10, 1
    add r8, r8, r10
    addi r9, r9, 1
    b Myst2Count
Myst2Counted:
    cmpwi r8, 0
    beq- Drop2Vanilla
    stw r6, 0x30(r1)
    stw r7, 0x34(r1)
    mr r3, r8
    %call(randi)
    lwz r6, 0x30(r1)
    lwz r7, 0x34(r1)
    li r9, 0
Myst2Walk:
    lbzx r10, r6, r9
    andi. r10, r10, 1
    beq- Myst2Next
    cmpwi r3, 0
    beq- Myst2Chosen
    subi r3, r3, 1
Myst2Next:
    addi r9, r9, 1
    cmpw r9, r7
    blt+ Myst2Walk
    li r9, 0
Myst2Chosen:
    %lwi(r6, RandTable)
    lbzx r6, r6, r9
    stw r6, PreRollOff(r26)      # fresh hidden roll for the match
    b Drop2Vanilla

Drop2Vanilla:
    li r26, 0x29
Drop2Done:
    %lwi(r11, DropChoice)
    stw r26, 0(r11)
    lwz r3, 0x28(r1)
    lwz r4, 0x2C(r1)
    lwz r0, 0x44(r1)
    mtlr r0
    addi r1, r1, 0x40
}

HOOK @ $806892C8
{
    %lwi(r5, DropChoice)
    lwz r5, 0(r5)
}



