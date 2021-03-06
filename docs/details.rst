Implementation details
======================

As hexabomb uses netorcai_ and therefore the `netorcai metaprotocol`_,
this page first defines the game-dependent part of the protocol,
which is essentially the format of the players' Actions_ and of the `Game state`_.
This page then answers frequently asked questions.

In netorcai, players are identified by a unique number :math:`playerID`.
In hexabomb, the color of a player is set to :math:`playerID+1`.
This is because color 0 is reserved for neutral cells.

Actions
-------

On each turn, players send their actions in a TURN_ACK_ netorcai message.

An action is represented as a JSON_ object with the following fields.

- ``id`` (number): The character unique identifier.
- ``movement`` (string): The type of action. Must be one of the following.

  - ``move`` if one wants the character to move.
  - ``bomb`` if one wants the character to drop a bomb.
  - ``revive`` if one wants the character to be revived.

Other fields are required depending on the desired ``movement``.

- ``direction`` (string): The desired direction for ``move`` movements.
  Must either be ``x+``, ``y+``, ``z+``, ``x-``, ``y-``, or ``z-``.
- ``bomb_range`` (number) and ``bomb_delay`` (number):
  The desired bomb range and delay for ``bomb`` movements.
  Both must be respect :math:`\{n \in \mathbb{N}\ |\  2 \leq n \leq 4\}`.
- (No parameters are required for ``revive`` movements.)

Actions examples
~~~~~~~~~~~~~~~~

The following example shows the actions taken by one player during one turn.

- Character 0 wants to move one cell towards the :math:`x^+` direction.
- Character 1 wants to drop a bomb on its current cell.
  The bomb should have a delay of 3 turns and a range of 3 cells.
- Character 2 wants to revive (on the cell where it died).

.. code-block:: json

    [
        {"id":0, "movement":"move", "direction":"x+"},
        {"id":1, "movement":"bomb", "bomb_delay":3, "bomb_range":3},
        {"id":2, "movement":"revive"}
    ]

Application of actions
~~~~~~~~~~~~~~~~~~~~~~

hexabomb applies the actions in best effort.
It will first try to apply each action in a given order,
then try to apply failed actions until convergence of the game state.

The order into which the actions are applied is described in the following algorithm.
Feel free to read the actual implementation in `hexabomb's source code`_ for more details.

.. code-block:: algorithm

    Do
    |   For each player in order of actions reception
    |   |   For each action in player-specified order
    |   |   |   Try to apply action if it has not been already applied successfully
    While (game state has been modified)

Game state
----------

hexabomb describes and sends the game state in DO_INIT_ACK_ and DO_TURN_ACK_ netorcai messages.
Players receive the game state described here in GAME_STARTS_, TURN_ and GAME_ENDS_ netorcai messages.

The game state is a JSON_ object with the following fields.

- ``cells``: An array of cells. Each cell is an object with the following fields.

    - ``q`` (number): The cell :math:`q` axial coordinate.
    - ``r`` (number): The cell :math:`r` axial coordinate.
    - ``color`` (number): The cell color.
      0 means neutral.
      Otherwise, means the cell belongs to player with :math:`playerID=color-1`

- ``characters``: An array of characters. Each character is an object with the following fields.

    - ``id`` (number): The character unique identifier.
    - ``color`` (number). The character color. Means the character belongs to player with :math:`playerID=color-1`.
    - ``q`` (number): The :math:`q` axial coordinate of the cell the player is in.
    - ``r`` (number): The :math:`r` axial coordinate of the cell the player is in.
    - ``alive`` (boolean): Whether the character is alive or not.
    - ``revive_delay`` (number): The number of turns before which the player can be revived. Dead characters can only be revived when it reaches 0. -1 for alive characters.
    - ``bomb_count`` (number): The number of bombs the character holds. Either 0, 1 or 2. Increased by 1 every 10 turns (with a maximum of 2).

- ``bombs``: An array of bombs. Each bomb is an object with the following fields.

    - ``color`` (number): The bomb color. Means the bomb belongs to player with :math:`playerID=color-1`.
    - ``range`` (number): The bomb range (AKA explosion radius), in number of cells.
    - ``delay`` (number): The bomb delay. Bombs explode when it reaches 0.
    - ``q`` (number): The :math:`q` axial coordinate of the cell the bomb is in.
    - ``r`` (number): The :math:`r` axial coordinate of the cell the bomb is in.

- ``explosions``: An object of cells that exploded this turn. The key is the color of the exploded cells, while the value is an array of objects with the following fields.

    - ``q`` (number): The :math:`q` axial coordinate of the cell that just exploded.
    - ``r`` (number): The :math:`r` axial coordinate of the cell that just exploded.

- ``cell_count``: An object where keys are **player identifiers** (not colors!) and values are their associated number of cells.
- ``score``: An object where keys are **player identifiers** (not colors!) and values are their associated score.

Game state example
~~~~~~~~~~~~~~~~~~

The following example shows a game state.

- There are three cells. Two belongs to first player, the last belongs to the other player.
- There are two characters. Only one of them is alive. The other cannot be revived right away, but it will be revivable next turn.
- There is one bomb.

.. code-block:: json

    {
      "cells":[
        {"q":0, "r":0, "color":1},
        {"q":0, "r":1, "color":2},
        {"q":0, "r":2, "color":2},
        {"q":1, "r":1, "color":2}
      ],
      "characters":[
        {"id":0, "color":1, "q":0, "r":0, "alive": true, "revive_delay":-1},
        {"id":1, "color":2, "q":0, "r":2, "alive":false, "revive_delay": 3}
      ],
      "bombs": [
        {"color":1, "range":3, "delay":2, "q":0, "r":1}
      ],
      "explosions": {
        "2": [
          {"q":0, "r":2},
          {"q":1, "r":1}
        ]
      },
      "cell_count":{
        "0": 2,
        "1": 3
      },
      "score":{
        "0": 8,
        "1": 21
      }
    }


How is a turn simulated?
------------------------

On each turn, hexabomb does the following steps in order.
Once again, feel free to read `hexabomb's source code`_ in case of doubt.

#. Apply players actions (see `Application of actions`_)
#. Reduce the revive delay of dead characters.
#. Increase the bomb count of all characters (every 10 turns).
#. Reduce bomb delays,
   explode those reaching a delay of 0,
   compute chain reactions then
   color exploded cells and kill any character on them.
#. Update the cell count and score of each player.

.. _JSON: https://www.json.org/index.html
.. _netorcai: https://github.com/netorcai/netorcai/
.. _netorcai metaprotocol: https://netorcai.readthedocs.io/en/latest/metaprotocol.html
.. _DO_INIT_ACK: https://netorcai.readthedocs.io/en/latest/metaprotocol.html#do-init-ack
.. _DO_TURN_ACK: https://netorcai.readthedocs.io/en/latest/metaprotocol.html#do-turn-ack
.. _GAME_STARTS: https://netorcai.readthedocs.io/en/latest/metaprotocol.html#game-starts
.. _GAME_ENDS: https://netorcai.readthedocs.io/en/latest/metaprotocol.html#game-ends
.. _TURN: https://netorcai.readthedocs.io/en/latest/metaprotocol.html#turn
.. _TURN_ACK: https://netorcai.readthedocs.io/en/latest/metaprotocol.html#turn-ack
.. _hexabomb's source code: https://github.com/netorcai/hexabomb/blob/master/src
