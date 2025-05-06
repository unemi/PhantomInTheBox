# BOIDS GPU
A flocking simulator utilising multi-threading on CPU and compute shader on GPU based on Craig Reynolds' BOIDS algorithm.
It runs at about 60 FPS for 200K agents, 30 FPS for 800K agents, and 20 FPS for 1M agents depending on the parameter values, on MacBook Pro M1 Max, CPU 10 cores
when compiled with `-Ofast` option.
MacOS 12 or higher on Apple Silicon CPU is required.

This software works together with another application module
*DepthCamSenderRS* to make the flock react to the visitor's gesture. It is assumed to run on a computer equipped with an  Intel$^Ⓡ$ Realsense™ D435 depth camera.
This module works with open source libraries,
*libusb* and *librealsense*.
These libraries do not work well out of the box, but they will work after a few attempts to allocate a proper memory using a combination of *sudo rs-enumerate-devices* and *realsense-viewer*. 

---
© Tatsuo Unemi, 2024, 2025.
