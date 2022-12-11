# Parallel-Ray-Tracer-Regent
Ray tracer with parallelism enabled using Regent Language.
Developer: Lovish Chopra (lovish@stanford.edu)
CS315B Parallel Computing Research Project
------------------------------------------------
This program uses a great task-based programming language Regent to run ray-tracing for a scene consisting of multiple spheres, lights and a camera. The
ray tracing operation has been implemented in an iterative manner instead of recursive to make it suitable for task-based programming.

The algorithm handles the following features:
- Diffuse lighting from point lights to objects
- Specular reflections
- Ambient shading
- Ray reflection
- Ray transmission
------------------------------------------------
Sample run:
regent raytrace.rg -i objects.txt -c camera.txt -l lights.txt -height 1080 -width 1920 -depth 4 -o output.png -p 8 -ll:cpu 8 -l:util 1
NOTE: Output image might be better visible at high brightness.
------------------------------------------------
Files:
- object.txt: Stores the details of all the objects.
    - The file should start with the number of objects in the first line. If the number specified is less than the actual number of objects 
      present in the file, the system will pick the number of objects specified in the first line. If the number specified is greater than
      the actual number of objects present in the file, the code will throw an error.
    - Each object has the following kind-of format:
        Example: sphere 15 2 2 3 d 0.3 0.4 0.6 s 0.1 0.1 0.1 sh 500 ior 1.05 t 0.98
        Here, the first string is the type of object. Currently, only 'sphere' is supported. 
        The next three numbers (15, 2, 2) are the center of the sphere, next number 3 is the radius of the sphere.
        The next four inputs d 0.3 0.4 0.6 is the diffuse colour in order R G B. The colour is represented as a factor from 0 to 1.
        The next four inputs s 0.1 0.1 0.1 is the specular color of the sphere object in order R G B, represented as a factor from 0 to 1.
        The next two inputs sh 500 is the specular hardness.
        The next two inputs ior 1.05 is the IOR of the material.
        The next two inputs t 0.98 is the transmission.
    - To support more kind of objects, 
        - Add support for it in fspace Object in raytrace.rg
        - Add support for parsing the object data in task initialize_camera_film_objects in raytrace.rg.
        - Add support for finding object intersection with ray in terra intersection in raytrace.rg.

- camera.txt: Stores the camera-related data
    - The first line of the file stores the location in the form of 'loc x y z', which means that camera is located at (x, y, z).
    - The next three lines of the file store the top left, top right and bottom left locations of the film plane in the form of 'tl/tr/bl x y z'.
        - Ideally, it is assumed that the plane is rectangular, though it is not necessary and hence, no check is made against the same.
        - Ideally, user should ensure that the output height and width have the same aspect ratio as the film plane, otherwise output image will be distorted.

- light.txt: Stores the lighting information.
    - First line stores the number of lights in the scene n.
    - Next n lines store the light information in the following kind-of format:
        Example: light 0 5 0 1 0 1 100
        The first three numbers (0, 5, 0) denote the position of light.
        The next three numbers (1, 0, 1) denote the color of light in R G B format. The color is denoted as a factor from 0 to 1.
        The last numebr denotes the light energy.
    - The last line has the ambient shading of the light. It has the format 'ambient r g b', where r/g/b are colors from 0 to 1.

