# RoboBlast Multiplayer
## About
This test game was created to learn multiplayer in Godot using the demo project [RoboBlast](https://github.com/gdquest-demos/godot-4-3d-third-person-controller) with the [EOS Godot addon](https://github.com/3ddelano/epic-online-services-godot). The game is a 3D platformer where players fight enemies and collect coins. Players can either host their own game or connect to an existing one.

## How to get the game working

There are some things that need to be done before the online features will work.

First, you will need to create an Epic Games account and set up an organization in their developer portal if you haven't done so already. This is required if you want to use the EOS Godot addon for this project and any other project you work on. To do this, just follow the instructions on how to set up your own organization and product from the Epic Game's website: https://dev.epicgames.com/docs/epic-online-services/eos-get-started/services-quick-start#step-1---set-up-an-epic-games-account-and-organization

You will also need to create an epic product, which will contain the game's client and product credentials. These are needed for the addon to access Epic Online Service's backend. To get an epic product up and running, follow these steps:

* Sign into your Epic Games account and go to the developer portal
* From the developer portal, click on "New Product" from the menu on the left. Type in the name of your product and click "Create Product". Once your product is created, it should show up in the list of products under "Your Products" in the developer portal.
* Next to the product's name, click the cog icon.
* Under "Clients", there should be a big empty section where it says "No clients yet". Click on the blue link below it to go to the clients section.
* In the clients section under "Clients", click the "Add New Client" button. 
* In this menu, simply type in a client name for your client.
* In that same menu, click the "Add new client policy" button that should be right below where you typed in your client's name. This will bring up a new menu to create a client policy.
* Type in the name of your new client policy. Under "Client policy type" select the "Peer2Peer" option, and then hit "Add new client policy".
* Once you've created your new client policy, it should have brought you back to the create client menu. Hit "Create Client", and your new client should have been created with the new client policy attached.

And this is it for setting up an epic product. 

Next, you need to grab the product's credentials and paste them into a file called `.env` at the root of your project (you will need to create that file, and make sure the name stays empty). An autoloaded script `eos_credentials.gd` will read these values using `env.gd`. This gdscript file is used to store important product credentails and are accessed by the game when it attempts to create and initialize the EOS platform.

Example .env file format:
```
PRODUCT_NAME="My Game"
PRODUCT_VERSION="1.0.0"
PRODUCT_ID="your_product_id"
SANDBOX_ID="your_sandbox_id"
DEPLOYMENT_ID="your_deployment_id"
CLIENT_ID="your_client_id"
CLIENT_SECRET="your_client_secret"
ENCRYPTION_KEY="64_character_random_string"
```

You can find the product's credentials in the product's settings in the developer's portal (The same place that you created your first client.)

Just copy and paste each key into their corresponding fields in `.env`. The `ENCRYPTION_KEY` is the last field in the file and it is a 64 character hexidecimal value that is used to encrypt your product credentials. This key is not important for this sample project and can be skipped.

And that should be it for setting up the game.

## How to host/connect to another game

Hosting and connecting to another game is easy. When you start the game, you will be given two options; "Online" or "Offline". Simply wait for the online services to be initialised, at which point the "Online" button should no longer be greyed out, and press "Online". To host a lobby, simply fill the fields below "HOST A LOBBY" and press "Host". To join a lobby, you can either select a lobby in the list of public lobbies - which you can refresh with the "Refresh" button - and press "Join", or ask the join code to the host, paste it in the matching field, and press "Resolve". Note that if the host started the game already, the lobby will no longer be public, so at that point, you need the join code to join their game.
