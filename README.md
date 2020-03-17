```

_______________________________________________________________________________________________________________
 _____/\\\\\\\\\\\_______/\\\\\\\\\\\______/\\\\\\\\\______/\\\____________________/\\\\\\\\\__/\\\________/\\\_
  ___/\\\/////////\\\___/\\\/////////\\\__/\\\///////\\\___\/\\\_________________/\\\////////__\/\\\_______\/\\\_
   __\//\\\______\///___\//\\\______\///__\/\\\_____\/\\\___\/\\\_______________/\\\/___________\//\\\______/\\\__
    ___\////\\\___________\////\\\_________\/\\\\\\\\\\\/____\/\\\______________/\\\______________\//\\\____/\\\___
     ______\////\\\___________\////\\\______\/\\\//////\\\____\/\\\_____________\/\\\_______________\//\\\__/\\\____
      _________\////\\\___________\////\\\___\/\\\____\//\\\___\/\\\_____________\//\\\_______________\//\\\/\\\_____
       __/\\\______\//\\\___/\\\______\//\\\__\/\\\_____\//\\\__\/\\\______________\///\\\______________\//\\\\\______
        _\///\\\\\\\\\\\/___\///\\\\\\\\\\\/___\/\\\______\//\\\_\/\\\\\\\\\\\\\\\____\////\\\\\\\\\______\//\\\_______
         ___\///////////_______\///////////_____\///________\///__\///////////////________\/////////________\///________
          _______________________________________________________________________________________________________________

```

# UGA SSRL Computer Vision

This computer vision software is for the [University of Georgia Small Satellite Research Laboratory](smallsat.uga.edu)'s MOCI (Multiview Onbloard Computational Imager) Satellite Mission. If you utilize this software please cite the papers listed below.

## Create the following directories if they do not exist
bin, data, obj, out, src, util
(util, data, and src should be in repository)

## File Naming Convention
If a file has CUDA in it of any sort -> .cu and its header -> .cuh.
All other files can be .cpp and .h

## Dependencies and Conventions

Required:
  * libpng-dev
  * libtiff-dev
  * g++
  * gcc
  * nvcc
  * CUDA 10.0

You may need to create the following directories: `bin, data, obj, out, src, util` (util, data, and src should be in repository)

## Intended Hardware

TODO write about the indented hardware

## Compilation

When making you should use the SM of your arch, you do this by setting the `SM` variable. I also recommend doing a multicore make with the `-j` flag. See below, where `#` are digits of integers:

All executables can be generated by simply using `make -j# SM=##`, addtionally neither the `-j` or the `SM` variable are nessesary. However, if these are not used then compilation will take much, much longer.

```
make sfm -j# SM=##
```

| Device                               | Recommended          | SM |
|:------------------------------------:|:--------------------:|:--:|
| Jetson Nano                          | `make sfm -j4 SM=53` | 53 |
| TX1                                  | `make sfm -j2 SM=53` | 53 |
| TX2 / TX2i                           | `make sfm -j6 SM=62` | 62 |
| Jetson Xavier                        | `make sfm -j6 SM=72` | 72 |
| Ubuntu 16.04+ with GTX 1060/1070     | `make sfm -j8 SM=61` | 61 |

You can also clean out the repo, to just have the standard files again, with

```
make clean
```

## Documentation
* Generate Doxygen by executing `doxygen doc/doxygen/Doxyfile` from within the projects root directory
* index.html will be available in doc/doxygen/documentation/html and will allow traversal of the documentation

## Running
| Flag              | Command Line Argument          | Details                      |
|:-----------------:|:------------------------------:|:----------------------------:|
| -i or --image     | `<path/to/single/image>`       | absolute or relative         |
| -d or --directory | `<path/to/directory/of/images>`| absolute or relative         |
| -s or --seed      | `<path/to/seed/image>`         | absolute or relative         |
| -np or --noparams |             N/A                | signify no use of params.csv |


### Full Pipeline

The main program is under bin saved as `SFM` and can be run with `./SFM`

There are addtional separate pipelines (compiled only if specified at make time) in the `/bin` directory. To learn about the pipeline,
you can find information on SIFT can be learned here: [Anatomy of SIFT](http://gitlab.smallsat.uga.edu/Caleb/anatomy-of-sift/blob/master/Anatomy%20of%20SIFT.pdf), this
sn't Lowe's original thing but it explains it pretty well. You should also see the latex doc that has been made, [located here](https://gitlab.smallsat.uga.edu/payload_software/Tegra-SFM/blob/master/doc/paper/main.pdf) - this is
known as the [Algorithm Theoretical Basis Document](https://gitlab.smallsat.uga.edu/payload_software/Tegra-SFM/blob/master/doc/paper/main.pdf).

## Source

Source files for the nominal program are located in the `src` folder. Some additional programs are located in the `util` folder.
Dependences for the source file are list here, but dependencies for the util files may vary.

## Camera Parameters

The image rotation encodes which way the camera was facing as a [rotation of axes](https://en.wikipedia.org/wiki/Rotation_of_axes) around the individual x, y, and z axes in R3. This, along with a physical position in R3, should be passed in by the ADCS. All other parameters should be known. The focal length is usually on the order of mm and the dpix is usually on the order of nm.

| Data type       | Variable Name     |  SI unit        | Description                                |
|:---------------:|:-----------------:|:---------------:|:------------------------------------------:|
| `float3`        | `cam_pos`         | Kilometers      |  The x,y,z camera position                 |
| `float3`        | `cam_rot`         | Radians         |  The x,y,z camera rotation                 |
| `float2`        | `fov`             | Radians         |  The x and y field of view                 |
| `float`         | `foc`             | Meters          |  The camera's focal length                 |
| `float2`        | `dpix`            | Meters          |  The physical dimensions of a pixel well   |
| `long long int` | `timeStamp`       | UNIX timestamp  |  A UNIX timestap from the time of imaging  |
| `uint2`         | `size`            | Pixels          |  The x and y pixel size of the image       |

## File Formats

### ASCII Camera Parameters - `.csv` ASCII encoded file

The ASCII encoded files that contain camera parameters should be included in the same directory as the images you wish to run a reconstruction on. It is required that the file be named `params.csv`. The file consists of the `Image.camera` struct parameters  (mentioned above for ease) in order. The format is as follows:


```
filename,x position,y position, z position, x rotation, y rotation, z rotation, x field of view, y field of view, camera focal length, x pixel well size, y pixel well size, UNIX timestamp, x pixel count, y pixel count
```

the files should be listed in a numerical order, each camera should be on one line and end with a `,`

and example of this is:

```
ev01.png,781.417,0.0,4436.30,0.0,0.1745329252,0.0,0.19933754453,0.19933754453,0.16,0.4,0.4,1580766557,1024,1024,
ev02.png,0.0,0.0,4500.0,0.0,0.0,0.0,0.19933754453,0.19933754453,0.16,0.4,0.4,1580766557,1024,1024,
```

### Binary Camera Parameters - `.bcp` file type

This is the binary version of the ascii format.

### Image File Formats - `.png` , `.tiff` , `.jpg`

TODO information about image support limitations here

### Point Clouds - `.ply` stanford PLY format

TODO information about ply support and limitations here

### Match Files - unknown

TODO Match file support here

Check out the [contributors guide](CONTRIB.md) for imformation on contributions

# TODO
* ensure that thrust functions are usi ng GPU
* more documentations

## Generating Test Data

TODO fill out information about how to make test data

# Citations

Upon usage please cite one or more of the following:

### Hardware Related Citation:

[Towards an Integrated GPU Accelerated SoC as a Flight Computer for Small Satellites](https://ieeexplore.ieee.org/document/8741765)

```
@inproceedings{TowardsAdams2019,
  doi = {10.1109/aero.2019.8741765},
  url = {https://doi.org/10.1109/aero.2019.8741765},
  year = {2019},
  month = mar,
  publisher = {{IEEE}},
  author = {Caleb Adams and Allen Spain and Jackson Parker and Matthew Hevert and James Roach and David Cotten},
  title = {Towards an Integrated {GPU} Accelerated {SoC} as a Flight Computer for Small Satellites},
  booktitle = {2019 {IEEE} Aerospace Conference}
}
```

### Pipeline Related Citation:

[A Near Real Time Space Based Computer Vision System for Accurate Terrain Mapping](https://digitalcommons.usu.edu/cgi/viewcontent.cgi?article=4216&context=smallsat)

```
@inproceedings{CVAdams2018,
  title={A Near Real Time Space Based Computer Vision System for Accurate Terrain Mapping},
  author={Adams, Caleb},
  journal={32nd Annual AIAA/USU Conference on Small Satellites},
  year={2018},
  publisher={AIAA}
}
```

### Use of Library Structure Citation:

TBD

### Use of 3D reconstruction Citation:

TBD











<!-- yeet -->
