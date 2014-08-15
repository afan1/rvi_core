Copyright (C) 2014, Jaguar Land Rover

This document is licensed under Creative Commons
Attribution-ShareAlike 4.0 International.

# REMOTE VEHICLE INTERACTION (RVI)

This document gives a brief introduction to the RVI project and how to 


This 
Better documentation coming soon.

Preqequisites.
Erlang R16B01 or later.
Make.
curl


To build:

$ make 


Window 1: Start the backend (server) node:
$ make run_backend


Window 2: Start the device node
$ make run_device


Window 4: Simulate a service that is registered with the backend node
$ nc -l 8901

Window 3: Send a register service JSON RPC command to the backend server
$ cd curl
$ sh register_backend.sh

Window 4: Send a message to the device that is to be forwarded to the backend node
          and its simulated service (nc -l 8901)

$ cd curl
$ sh device_message.sh

Questions can be posted to the AGL RVI list:
http://lists.linuxfoundation.org/mailman/listinfo/automotive-eg-rvi

Tizen 3.0 Intel

Build service Tizen + RVI -> release.

