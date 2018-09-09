import std.algorithm;
import std.conv;
import std.exception;
import std.format;
import std.json;
import std.range;
import std.typecons;

import netorcai.json_util;

import board;
import bomb;

struct Character
{
    immutable uint id;
    immutable uint color;
    bool alive = true;
    Position pos;
}

class Game
{
    private
    {
        Board _board;
        Bomb[] _bombs;
        Character[] _characters;

        Position[][int] _initialPositions; /// Initial positions for each color
    }

    this(in JSONValue initialMap)
    {
        enforce(initialMap.type == JSON_TYPE.OBJECT,
            "initial map is not an object");
        _board = new Board(initialMap["cells"]);

        auto initPos = initialMap["initial_positions"];
        enforce(initPos.type == JSON_TYPE.OBJECT,
            "initial_positions is not an object");
        foreach(key, value; initPos.object)
        {
            uint color;
            try { color = to!uint(key); }
            catch (Exception) { enforce(false, format!"invalid key='%s' in initial_positions"(key)); }

            enforce(value.type == JSON_TYPE.ARRAY,
                "initial positions are not an array for key=" ~ key);
            enforce(value.array.length > 0,
                "initial positions are empty for key=" ~ key);

            foreach(i, o; value.array)
            {
                enforce(o.type == JSON_TYPE.OBJECT,
                    "Element " ~ to!string(i) ~ " of initial_positions should be an object");
                Position p;
                p.q = o["q"].getInt;
                p.r = o["r"].getInt;

                _initialPositions[color] ~= p;
            }
        }

        checkInitialPositions(_initialPositions, _board);
    }
    unittest
    {
        string s = `[]`;
        assertThrown(new Game(s.parseJSON));
        assert(collectExceptionMsg(new Game(s.parseJSON)) ==
            "initial map is not an object");

        s = `{"cells":[], "initial_positions":4}`;
        assertThrown(new Game(s.parseJSON));
        assert(collectExceptionMsg(new Game(s.parseJSON)) ==
            "initial_positions is not an object");

        s = `{"cells":[], "initial_positions":{"bouh":1}}`;
        assertThrown(new Game(s.parseJSON));
        assert(collectExceptionMsg(new Game(s.parseJSON)) ==
            "invalid key='bouh' in initial_positions");

        s = `{"cells":[], "initial_positions":{"0":1}}`;
        assertThrown(new Game(s.parseJSON));
        assert(collectExceptionMsg(new Game(s.parseJSON)) ==
            "initial positions are not an array for key=0");

        s = `{"cells":[], "initial_positions":{"0":[]}}`;
        assertThrown(new Game(s.parseJSON));
        assert(collectExceptionMsg(new Game(s.parseJSON)) ==
            "initial positions are empty for key=0");

        s = `{"cells":[], "initial_positions":{"0":[4]}}`;
        assertThrown(new Game(s.parseJSON));
        assert(collectExceptionMsg(new Game(s.parseJSON)) ==
            "Element 0 of initial_positions should be an object");
    }

    /// Checks whether initial positions are fine. Throw Exception otherwise.
    static void checkInitialPositions(in Position[][int] positions, in Board b)
    {
        enforce(positions.length > 0, "There are no initial positions");
        enforce(isPermutation(positions.keys(), iota(0, positions.length)),
            "Initial positions are missing for some players");
        enforce(positions.values.findAdjacent!"a.length != b.length".empty,
            "All players do not have the same number of positions");

        bool[Position] _marks;
        foreach(posArr ; positions)
        {
            foreach(pos ; posArr)
            {
                enforce(b.cellExists(pos),
                    "There is no cell at " ~ pos.toString);
                enforce(!b.cellAt(pos).isWall,
                    "Cell is a wall at " ~ pos.toString);
                enforce(!(pos in _marks),
                    "Duplication of initial cell " ~ pos.toString);
                _marks[pos] = true;
            }
        }
    }
    unittest
    {
        Board b = generateEmptyBoard;
        Position[][int] positions;
        assertThrown(checkInitialPositions(positions,b));
        assert(collectExceptionMsg(checkInitialPositions(positions,b)) ==
            "There are no initial positions");

        positions = [
            0: [],
            1: [],
            3: []
        ];
        assertThrown(checkInitialPositions(positions,b));
        assert(collectExceptionMsg(checkInitialPositions(positions,b)) ==
            "Initial positions are missing for some players");

        positions = [
            0: [Position(0,0)],
            1: [Position(0,1)],
            2: [Position(0,2), Position(0,3)]
        ];
        assertThrown(checkInitialPositions(positions,b));
        assert(collectExceptionMsg(checkInitialPositions(positions,b)) ==
            "All players do not have the same number of positions");

        positions = [
            0: [Position(0,8)],
        ];
        assertThrown(checkInitialPositions(positions,b));
        assert(collectExceptionMsg(checkInitialPositions(positions,b))
            .startsWith("There is no cell at"));

        positions = [
            0: [Position(0,0)],
        ];
        Board bwall = new Board(`[{"q":0, "r":0, "wall":true}]`.parseJSON);
        assertThrown(checkInitialPositions(positions,bwall));
        assert(collectExceptionMsg(checkInitialPositions(positions,bwall))
            .startsWith("Cell is a wall at"));

        positions = [
            0: [Position(0,0)],
            1: [Position(0,1)],
            2: [Position(0,0)]
        ];
        assertThrown(checkInitialPositions(positions,b));
        assert(collectExceptionMsg(checkInitialPositions(positions,b))
            .startsWith("Duplication of initial cell"));
    }

    // Generate the initial characters. Throw Exception on error
    void placeInitialCharacters(in int nbPlayers)
    in
    {
        assert(_characters.empty);
    }
    body
    {
        enforce(_initialPositions.length >= nbPlayers,
            format!"Too many players (%d) for this map (max=%d)."(
                nbPlayers, _initialPositions.length));

        uint characterID = 0;
        foreach(playerID; 0..nbPlayers)
        {
            foreach(pos; _initialPositions[playerID])
            {
                Character c = {id: characterID, color:playerID+1, pos:pos};
                _characters ~= c;
                characterID += 1;
            }
        }
    }
    unittest
    {
        Game g = new Game(`{
          "cells":[
            {"q":0, "r":0, "wall":false}
          ],
          "initial_positions":{
            "0": [{"q":0, "r":0}]
          }
        }`.parseJSON);
        assertThrown(g.placeInitialCharacters(2));
        assertNotThrown(g.placeInitialCharacters(1));
        assert(g._characters[0].pos == Position(0,0));
    }

    /// Generate a JSON description of the current characters
    private JSONValue describeCharacters() pure const
    out(r)
    {
        assert(r.type == JSON_TYPE.ARRAY);
    }
    body
    {
        JSONValue v = `[]`.parseJSON;

        foreach(c; _characters)
        {
            JSONValue cValue = `{}`.parseJSON;
            cValue.object["id"] = c.id;
            cValue.object["color"] = c.color;
            cValue.object["q"] = c.pos.q;
            cValue.object["r"] = c.pos.r;
            cValue.object["alive"] = c.alive;

            v.array ~= cValue;
        }

        return v;
    }

    private JSONValue describeBombs() pure const
    out(r)
    {
        assert(r.type == JSON_TYPE.ARRAY);
    }
    body
    {
        JSONValue v = `[]`.parseJSON;

        foreach(b; _bombs)
        {
            JSONValue cValue = `{}`.parseJSON;
            cValue.object["color"] = b.color;
            cValue.object["range"] = b.range;
            cValue.object["delay"] = b.delay;
            cValue.object["q"] = b.position.q;
            cValue.object["r"] = b.position.r;
            cValue.object["type"] = b.type;

            v.array ~= cValue;
        }

        return v;
    }
    unittest
    {
        Game g = new Game(`{
          "cells":[
            {"q":0, "r":0, "wall":false},
            {"q":0, "r":1, "wall":false}
          ],
          "initial_positions":{
            "0": [{"q":0, "r":0}]
          }
        }`.parseJSON);
        assert(g.describeBombs == `[]`.parseJSON);

        g._bombs ~= Bomb(Position(0,1), 3, 5, BombType.thin, 7);
        assert(g.describeBombs.toString ==
            `[{"q":0, "r":1, "color":3, "range":5, "type":"thin", "delay":7}]`
            .parseJSON.toString);

        g._bombs ~= Bomb(Position(0,2), 4, 2, BombType.fat, 2);
        assert(g.describeBombs.toString ==
            `[{"q":0, "r":1, "color":3, "range":5, "type":"thin", "delay":7},
              {"q":0, "r":2, "color":4, "range":2, "type":"fat", "delay":2}]`
            .parseJSON.toString);
    }

    /// Generate a JSON description of the game state
    JSONValue describeInitialState() const
    out(r)
    {
        assert(r.type == JSON_TYPE.OBJECT);
    }
    body
    {
        JSONValue v = `{}`.parseJSON;
        v.object["cells"] = _board.toJSON;
        v.object["characters"] = describeCharacters;
        v.object["bombs"] = describeBombs;

        return v;
    }
    unittest
    {
        Game g = new Game(`{
          "cells":[
            {"q":0, "r":0, "wall":false},
            {"q":0, "r":1, "wall":false}
          ],
          "initial_positions":{
            "0": [{"q":0, "r":0}],
            "1": [{"q":0, "r":1}]
          }
        }`.parseJSON);
        g.placeInitialCharacters(2);
        assert(g.describeInitialState.toString == `{
            "bombs": [],
            "cells":[
              {"q":0, "r":0, "wall":false},
              {"q":0, "r":1, "wall":false}
            ],
            "characters":[
              {"id":0, "color":1, "q":0, "r":0, "alive":true},
              {"id":1, "color":2, "q":0, "r":1, "alive":true}
            ]
          }`.parseJSON.toString);
    }

    /**
     * Explode bombs, change board colors and kill characters if needed.
    **/
    private void doBombTurn()
    {
        alias ColorDist = Tuple!(uint, "color", int, "distance");
        ColorDist[Position] boardAlterations;
        Bomb[Position] explodedBombs;

        void updateBoardAlterations(ref ColorDist[Position] alterations, in int[Position] explosionRange, in uint color)
        {
            foreach(pos, dist; explosionRange)
            {
                if (pos in alterations)
                {
                    // Potential conflict.
                    if (dist < alterations[pos].distance)
                    {
                        // The new bomb is closer. The cell color is set to the new bomb's.
                        alterations[pos] = ColorDist(color, dist);
                    }
                    else if (dist == alterations[pos].distance)
                    {
                        // At least two bombs are at the same distance of this cell.
                        // If colors are different, reset the cell to a non-player color.
                        if (color != alterations[pos].color)
                            alterations[pos].color = 0;
                    }
                    // Otherwise, the previous bomb(s) were closer, the new bomb can be ignored for this cell.
                }
                else
                {
                    // Newly exploded cell.
                    alterations[pos] = ColorDist(color, dist);
                }
            }
        }

        // Reduce the delay of all bombs.
        // Compute the explosion range of 0-delay bombs
        foreach (ref b; _bombs)
        {
            b.delay = b.delay - 1;

            if (b.delay <= 0)
            {
                explodedBombs[b.position] = b;
                auto explosion = _board.computeExplosionRange(b);
                updateBoardAlterations(boardAlterations, explosion, b.color);
            }
        }

        // Until convergence: Explode bombs that are in exploded cells
        bool converged = false;
        do
        {
            auto newlyExplodedBombs = _bombs.filter!(b => !(b.position in explodedBombs)
                                                       &&  (b.position in boardAlterations));

            foreach (b; newlyExplodedBombs)
            {
                explodedBombs[b.position] = b;
                auto explosion = _board.computeExplosionRange(b);
                updateBoardAlterations(boardAlterations, explosion, b.color);
            }

            converged = newlyExplodedBombs.empty;
        } while(!converged);

        // Kill characters on exploded cells.
        auto killedCharacters = _characters.filter!(c => c.pos in boardAlterations);
        killedCharacters.each!((ref c) => c.alive = false);

        // Remove exploded bombs.
        _bombs = _bombs.remove!(b => b.position in explodedBombs);

        // Update the board
        foreach (pos, colorDist; boardAlterations)
        {
            _board.cellAt(pos).explode(colorDist.color);
        }
    }
    unittest // One single bomb explodes (kill chars and propagate color)
    {
        auto bombPosition = Position(0,3);
        uint bombColor = 1;
        uint bombRange = 3;

        auto previous = generateBasicGame;
        auto g = generateBasicGame;
        assert(g == previous);

        // Insert bomb
        g._bombs ~= Bomb(bombPosition, bombColor, bombRange, BombType.thin, 2);
        g._board.cellAt(bombPosition).addBomb;
        assert(g != previous);

        // First bomb turn (do not explode)
        g.doBombTurn;
        assert(g != previous);
        previous._board.cellAt(bombPosition).addBomb;
        previous._bombs = [Bomb(bombPosition, bombColor, bombRange, BombType.thin, 1)];
        assert(g == previous);

        // Second bomb turn (explode)
        g.doBombTurn;
        assert(g != previous);
        previous._bombs = [];
        auto explosion = previous._board.computeExplosionRange(
            Bomb(Position(0,3), bombColor, bombRange, BombType.thin, 42));

        foreach (pos; explosion.byKey)
            previous._board.cellAt(pos).explode(bombColor);

        foreach (ref c; previous._characters)
            c.alive = false;
        assert(g == previous);

        // Third turn (no bombs: nothing happens)
        g.doBombTurn;
        assert(g == previous);
    }
    unittest // Several bombs (domino effect)
    {
        auto previous = generateBasicGame;
        Game g = generateBasicGame;

        // Set some cells to color 42
        Position[] pos42 = [
            Position(0,0),
            Position(0,1),
            Position(0,2),
            Position(0,3),
            Position(1,2)
        ];
        pos42.each!(pos => g._board.cellAt(pos).explode(42));
        pos42.each!(pos => previous._board.cellAt(pos).explode(42));

        Bomb genBomb(Position pos, uint color)
        {
            return Bomb(pos, color, 10, BombType.thin, 10);
        }
        Bomb[] bombs = [
            // Central bomb
            Bomb(Position(0,0), 50, 10, BombType.thin, 1),
            // Border bombs
            genBomb(Position( 3, 0), 1),
            genBomb(Position( 3,-3), 2),
            genBomb(Position( 0,-3), 3),
            genBomb(Position(-3, 0), 4),
            genBomb(Position(-3, 3), 5),
            genBomb(Position( 0, 3), 6),
            genBomb(Position( 2, 1), 6),
        ];

        // Insert bombs
        g._bombs = bombs.dup;
        g._bombs.each!(b => g._board.cellAt(b.position).addBomb);
        assert(g != previous);

        previous._bombs = bombs.dup;
        previous._bombs.each!(b => previous._board.cellAt(b.position).addBomb);
        assert(g == previous);

        // First turn (central bomb explode -> all bombs explode)
        g.doBombTurn;
        previous._bombs = [];
        previous._characters.each!((ref c) => c.alive = false);

        uint[Position] colorAlterations = [
            // Newly central (50)
            Position( 0, 0): 50,
            Position( 1, 0): 50,
            Position( 1,-1): 50,
            Position( 0,-1): 50,
            Position(-1, 0): 50,
            Position(-1, 1): 50,
            Position( 0, 1): 50,
            // Newly 1
            Position( 3, 0): 1,
            Position( 3,-1): 1,
            // Newly 2
            Position( 3,-3): 2,
            Position( 3,-2): 2,
            Position( 2,-2): 2,
            Position( 2,-3): 2,
            // Newly 3
            Position( 0,-3): 3,
            Position( 1,-3): 3,
            Position( 0,-2): 3,
            Position(-1,-2): 3,
            // Newly 4
            Position(-3, 0): 4,
            Position(-2,-1): 4,
            Position(-2, 0): 4,
            Position(-3, 1): 4,
            // Newly 5
            Position(-3, 3): 5,
            Position(-3, 2): 5,
            Position(-2, 2): 5,
            Position(-2, 3): 5,
            // Newly 6 ( 0, 3)
            Position( 0, 3): 6,
            Position(-1, 3): 6,
            Position( 0, 2): 6,
            Position( 1, 2): 6, // shared with bomb( 2, 1) of same color
            // Newly 6 ( 2, 1)
            Position( 2, 1): 6,
            Position( 1, 1): 6,
            Position(-2, 1): 6,
            Position( 2,-1): 6,
            // Newly neutral
            Position( 2, 0): 0, // (3,0), (2,1)
        ];
        colorAlterations.each!((pos, color) => previous._board.cellAt(pos).explode(color));
        assert(g == previous);
    }

    override bool opEquals(const Object o) const
    {
        auto g = cast(const Game) o;
        return (this._board == g._board) &&
               (this._bombs == g._bombs) &&
               (this._characters == g._characters) &&
               (this._initialPositions == g._initialPositions);
    }

    override string toString()
    {
        return format!"{bombs=%s, characters=%s, initialPositions=%s, board=%s}"(
            _bombs, _characters, _initialPositions, _board);
    }
    unittest
    {
        auto g = new Game(`{
          "cells":[
            {"q":0,"r":0,"wall":false},
            {"q":0,"r":1,"wall":false}
          ],
          "initial_positions":{
            "0": [{"q":0, "r":0}],
            "1": [{"q":0, "r":1}]
          }
        }`.parseJSON);
        assert(g.toString == `{bombs=[], characters=[], initialPositions=[0:[{q=0,r=0}], 1:[{q=0,r=1}]], board={cells:[{q=0,r=1}:{color=0}, {q=0,r=0}:{color=0}], neighbors:[{q=0,r=1}:[{q=0,r=0}], {q=0,r=0}:[{q=0,r=1}]]}}`);

        g.placeInitialCharacters(2);
        assert(g.toString == `{bombs=[], characters=[Character(0, 1, true, {q=0,r=0}), Character(1, 2, true, {q=0,r=1})], initialPositions=[0:[{q=0,r=0}], 1:[{q=0,r=1}]], board={cells:[{q=0,r=1}:{color=0}, {q=0,r=0}:{color=0}], neighbors:[{q=0,r=1}:[{q=0,r=0}], {q=0,r=0}:[{q=0,r=1}]]}}`);

        g._bombs = [Bomb(Position(0,0), 1, 1, BombType.thin, 1)];
        g._board.cellAt(Position(0,0)).addBomb;
        assert(g.toString == `{bombs=[Bomb({q=0,r=0}, 1, 1, thin, 1)], characters=[Character(0, 1, true, {q=0,r=0}), Character(1, 2, true, {q=0,r=1})], initialPositions=[0:[{q=0,r=0}], 1:[{q=0,r=1}]], board={cells:[{q=0,r=1}:{color=0}, {q=0,r=0}:{color=0,bomb}], neighbors:[{q=0,r=1}:[{q=0,r=0}], {q=0,r=0}:[{q=0,r=1}]]}}`);
    }
}

private Game generateBasicGame()
{
    auto g = new Game(`{
      "cells":[
        {"q":-3,"r":0,"wall":false},
        {"q":-3,"r":1,"wall":false},
        {"q":-3,"r":2,"wall":false},
        {"q":-3,"r":3,"wall":false},
        {"q":-2,"r":-1,"wall":false},
        {"q":-2,"r":0,"wall":false},
        {"q":-2,"r":1,"wall":false},
        {"q":-2,"r":2,"wall":false},
        {"q":-2,"r":3,"wall":false},
        {"q":-1,"r":-2,"wall":false},
        {"q":-1,"r":-1,"wall":false},
        {"q":-1,"r":0,"wall":false},
        {"q":-1,"r":1,"wall":false},
        {"q":-1,"r":2,"wall":false},
        {"q":-1,"r":3,"wall":false},
        {"q":0,"r":-3,"wall":false},
        {"q":0,"r":-2,"wall":false},
        {"q":0,"r":-1,"wall":false},
        {"q":0,"r":0,"wall":false},
        {"q":0,"r":1,"wall":false},
        {"q":0,"r":2,"wall":false},
        {"q":0,"r":3,"wall":false},
        {"q":1,"r":-3,"wall":false},
        {"q":1,"r":-2,"wall":false},
        {"q":1,"r":-1,"wall":false},
        {"q":1,"r":0,"wall":false},
        {"q":1,"r":1,"wall":false},
        {"q":1,"r":2,"wall":false},
        {"q":2,"r":-3,"wall":false},
        {"q":2,"r":-2,"wall":false},
        {"q":2,"r":-1,"wall":false},
        {"q":2,"r":0,"wall":false},
        {"q":2,"r":1,"wall":false},
        {"q":3,"r":-3,"wall":false},
        {"q":3,"r":-2,"wall":false},
        {"q":3,"r":-1,"wall":false},
        {"q":3,"r":0,"wall":false}],
      "initial_positions":{
        "0": [{"q":0, "r":0}],
        "1": [{"q":0, "r":1}]
      }
    }`.parseJSON);

    g.placeInitialCharacters(2);
    return g;
}
