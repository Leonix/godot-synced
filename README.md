Godot Synced
============

Synced is a high-level networking framework for Godot game engine. It provides tools and design patterns
to facilitate making fast-paced multiplayer games with authoritative server architecture.

Synced is designed to be easy to grasp. It hides from game logic code most complexities inherent to networking.
In most cases you should code your game objects as if you were making a single player game.

TODO: describe more nice stuff here: input capture, fine-tuned synchronization, interpolation, lag compensation,
client-side prediction, low traffic footprint...

TODO: apologize for a very early dev stage and all the bugs and TODOs ;)

Getting started: example
------------------------

If you clone this repo, it contains a project with a game of Pong.

Getting started: add to existing game
-------------------------------------

1. Copy addons/synced to the same dir in your project.

2. Add `res://addons/synced/SyncManager.gd` as a singleton.

3. Attach a [Synced](godot-synced/addons/synced/Synced.gd) node as a child to all active game objects
   (Node2D or Spatial) that need to be synced over the network between peers. This will make the Server send
   their positions and rotations to all Clients 20 times per second, with smooth interpolation between frames.
   See Pong example game.

4. Instead of Godot's built-in `Input` class, you have to use `$synced.input` to read player input.
   `$synced` here means `Synced` object from (3) above that is a child of game object in question,
   and `$synced.input` is a (limited) drop-in replacement for Godot's Input class. What this does is: it makes
   all Clients send their mouse strokes and keyboard presses to Server for processing, as well as
   making the same strokes available locally on client for client-side prediction processing.
   See [paddle script](playground/pong/logic/paddle.gd) as an example.

5. Set up client-server connection as you would normally do via built-in Godot networking.
   See [lobby script](playground/pong/logic/lobby.gd) as an example.

This should launch and sync as long as Clients and Server have the same NodePaths for all objects.

To sync any property on your game objects, not just their positions, add `SyncedProperty` children to `Synced` object.
This also allows to customize how syncing should be done: reliably or unreliably, set up client-side-prediction,
and tweak interpolation settings.

TODO: describe more nice things: interpolation; client-side prediction for player's own movement;
lag compensation; spawn and sync dynamic game objects; add complex examples like animation sync;
tweak traffic footprint.

Class docs
----------

Nothing to show here yet, WIP. Code inside addons/synced has plenty of comments though. TODO.

Contacts
--------

I will launch a Discord server eventually. Until then, reach me via `WhiteVirus#2531` at Discord.


License
-------

Copyright 2021-2022 Leonid Vakulenko.

Licensed under the [MIT License](LICENSE.txt).
