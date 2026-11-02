# ASCII Snake - Group 10 / CIS303

A single-file 8086 assembly Snake game for CS125L. No external libraries, include files, or game assets are required.

## Files

- [src/snake.asm](src/snake.asm): current source, from the supplied SNAKE.ASM.
- [submission/CIS303_Group10_MP.txt](submission/CIS303_Group10_MP.txt): the same source in the course's required submission format.

The earlier src/snake_asciiv3.ASM remains as the existing historical version. Use **src/snake.asm** for the current game.

## Run in emu8086

1. Open src/snake.asm in emu8086.
2. Press **F5 (Emulate)** to assemble and load it, then click **Run**.
3. Enter a player initial A-Z and difficulty: **1 = Easy**, **2 = Normal**, **3 = Fast**.
4. Use **W/A/S/D** to turn. Eat **@** to increase the score and length; avoid **#** walls and your own body. **O** is the head and **o** is the body.
5. **X or Escape** ends the round. **R** restarts with the same settings; **E** exits after a round.

Invalid setup/menu inputs are re-prompted. Unsupported movement keys and immediate U-turns are ignored. Filling the 30x12 board wins at 357 points.

The bottom/right border coordinates use explicit constants **19** and **54** to avoid emu8086 4.08 misinterpreting nested EQU expressions as memory operands. Recompile the current source rather than loading an executable built from the older version.

## Build verification

The supplied source assembled in strict 8086/MASM-compatible mode with UASM 2.57: **zero errors and zero warnings**. The same source version previously passed 12 compiled-code test groups and an 8086 DOSBox-X smoke test. Interactive emu8086 play was not independently verified.

From the repository root, an optional UASM build command is:

```powershell
& 'C:\path\to\uasm64.exe' -0 -Zm -Zne -W4 -WX -mz -FoSNAKE.EXE src/snake.asm
```

Run that generated 16-bit DOS executable in DOSBox-X. Generated executables and build artifacts are not included in this branch. If you edit the assembly source, update the submission text copy as well.
