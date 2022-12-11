-- CS315B: Parallel Computing Research Project
-- Lovish Chopra
-- lovish@stanford.edu
-- This regent program can be used to ray trace objects using a spherical ray tracer.

-- Sample run:
-- regent raytrace.rg -i objects.txt -c camera.txt -l lights.txt -p 16 -ll:cpu 16 -ll:util 1
-- mpirun -n 1 -npernode 1 -bind-to none regent raytrace.rg -fcuda 1 -ll:gpu 1 -c camera.txt -i objects.txt -l lights.txt -height 1080 -width 1920 -p 40 -ll:gpu 1
import "regent"

-- Helper modules to handle command line arguments and saving of png files
local RayTraceConfig = require("raytrace_config")
local ray_trace_util = require("ray_trace_util")

-- Some C APIs for using in the code
local c = regentlib.c
local cmath = terralib.includec("math.h")
local cstring = terralib.includec("string.h")

-- Point struct is for declaring a point in space. It's given by its coordinates (x, y, z)
struct Point {
    x: float;
    y: float;
    z: float;
}

-- Vector struct is for declaring a vector in space. It's given by its direction (x, y, z)
-- While in general, the structure looks the same like point, but its essence is different
-- from that of a point, which is why we keep it separate.
struct Vector {
    x: float;
    y: float;
    z: float;
}

-- Color struct is for a color, which is given using its RGB values (r, g, b).
-- Note that in ray tracing, we define the color components to be of type float which has a
-- value generally between 0 to 1. To get the actual RGB value, we multiply the color float
-- with 255.
struct Color {
    r: float;
    g: float;
    b: float;
}

-- intColor struct is for the final color of the pixel in integer format. It is generally
-- obtained by multiplying Color struct by 255.
struct intColor {
    r: uint8;
    g: uint8;
    b: uint8;
}
 
-- Object field space is for storing objects. 
-- Currently, the supported objtype is sphere only. But the code has been generalized to 
-- support multiple object types.
-- Each sphere will have a center, radius. Along with that, they will also have diffuse color, 
-- specular color, specular hardness, ior and transmission
fspace Object {
    objtype: int8[20];
    center: Point;
    radius: float;
    diffuse_color: Color;
    specular_color: Color;
    specular_hardness: float;
    ior: float;
    transmission: float;
}

-- Ray field space is for storing the rays. Each ray has a starting location and a direction.
-- Along with that, the factor and depth are used to run the ray tracing in a smart DFS way.
-- For all initial rays, factor is 1 and depth is the input depth of ray tracing.
fspace Ray {
    loc: Point;
    dir: Vector;
    factor: float;
    depth: int;
}

-- Light field space is for storing the lights. Each light has a location, color and energy
-- associated with it.
fspace Light {
    loc: Point;
    color: Color;
    energy: float;
}

-- Pixel field space is for storing the final Pixels of the image. Each pixel will have an initial
-- ray with location as the camera location and direction from camera location to the pixel.
-- the color will store the final integer color value of the pixel.
fspace Pixel {
    ray: Ray;
    color: intColor;
}

-- Intersection Point field space is used for the output of the ray cast function, which returns
-- whether the ray intersected with some object, and if yes, which object.
fspace IntersectionPoint {
    hit_loc: Point;
    hit_norm: Vector;
    hit_idx: uint64;
    has_hit: bool;
}
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- Terra Functions for utility

-- Skip header from the file
terra skip_header(f : &c.FILE)
  var x : uint64
  c.fscanf(f, "%llu\n", &x)
end

-- Get the norm of a vector
terra Vector:norm()
  return cmath.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

-- Get the norm squared of a vector
terra Vector:normsq()
  return self.x * self.x + self.y * self.y + self.z * self.z
end

-- Return a normalized vector
terra Vector:normalized()
    var out: Vector
    var norm = self:norm()
    out.x = self.x / norm
    out.y = self.y / norm
    out.z = self.z / norm
    return out
end

-- Return dot product of two vectors
terra dot(a: Vector, b: Vector)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

-- Return abs of a float value
terra abs(a: float)
    if a >= 0 then
        return a
    else
        return -1 * a
    end
end

-- Subtract two vectors and find a - b
terra minus(a: Vector, b: Vector)
    return Vector{a.x - b.x, a.y - b.y, a.z - b.z}
end

-- Add two vectors and find a + b
terra plus(a: Vector, b: Vector)
    return Vector{a.x + b.x, a.y + b.y, a.z + b.z}
end

-- Add vector to point to reach a new point situated at a + b
terra plusPoint(a: Point, b: Vector)
    return Point{a.x + b.x, a.y + b.y, a.z + b.z}
end

-- Add two colors a + b
terra addColor(a: Color, b: Color)
    return Color{a.r + b.r, a.g + b.g, a.b + b.b}
end

-- Multiply vector by constant float b
terra vector_multc(a: Vector, b: float)
    return Vector{a.x * b, a.y * b, a.z * b}
end

-- Multiply color by constant float b
terra color_multc(a: Color, b: float)
    return Color{a.r * b, a.g * b, a.b * b}
end

-- Multiply two colors by simply multiplying their r, g, and b values
terra mult_colors(a: Color, b: Color)
    return Color{a.r * b.r, a.g * b.g, a.b * b.b}
end

-- Get vector between two points a and b. Vector from a to b is defined by b - a
terra get_vector(a: Point, b: Point)
    return Vector{b.x - a.x, b.y - a.y, b.z - a.z}
end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- Function to perform intersection between a ray and a sphere and return the intersection
-- Intersection is returned in the form of a float value di1, which is the distance of the
-- intersection point from the ray location via the ray direction.
-- Essentially, intersection point = ray_location + di1 * ray_direction
-- Logic of the code has been explained in https://www.lighthouse3d.com/tutorials/maths/ray-sphere-intersection/.
terra intersection(ray_origin: Point, ray_dir: Vector, sphere_origin: Point, radius: float)
    -- Normalize the ray
    ray_dir = ray_dir:normalized()

    -- Get the vector from ray origin to sphere origin
    var ray_to_sphere: Vector = get_vector(ray_origin, sphere_origin)

    -- Take the doc product of the normalized ray vector ray->sphere vector
    var rsd: float = dot(ray_to_sphere, ray_dir)

    -- Get the projection of the sphere center on the ray
    var pc = Point{rsd * ray_dir.x + ray_origin.x, rsd * ray_dir.y + ray_origin.y, rsd * ray_dir.z + ray_origin.z}

    -- If the dot product is negative, it means that the center of sphere is behind the ray origin.
    if rsd < 0 then 
        if ray_to_sphere:norm() >= radius then 
             -- In this case, if the ray is outside the sphere, we return a large number signifying no intersection
            return 9999999
        else 
             -- Else if the ray is inside the sphere, we return the intersection di1 calculated simply using mathematics
            var di1 : float = get_vector(ray_origin, pc):norm() - cmath.sqrt(radius * radius - get_vector(sphere_origin, pc):normsq())
            return di1
        end

    -- if ray is towards the sphere
    else
        if get_vector(sphere_origin, pc):norm() > radius then
            -- if the projection of the sphere origin on ray is outside the sphere, then ray crosses the sphere without intersecting it
            return 9999999
        else
            -- Else, the ray intersects the sphere at two points. Note: If ray is tangent to the sphere, then we say that the ray intersects
            -- at two points with both intersections being at the same point. In this case, dist = 0.
            var di1 : float
            var dist : float = cmath.sqrt(radius * radius - get_vector(sphere_origin, pc):normsq())
            if abs(rsd) >= radius then
                di1 = get_vector(ray_origin, pc):norm() - dist
            else
                di1 = get_vector(ray_origin, pc):norm() + dist
            end
            return di1
        end
    end
end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- Terra function to read camera location and store it in a camera_loc point
terra read_camera_loc(file_camera : &c.FILE)
    var str: int8[512]
    var camera_loc : Point
    -- Read the camera location and check if the string says 'loc'
    regentlib.assert(c.fscanf(file_camera, "%s %f %f %f\n", &str, &camera_loc.x, &camera_loc.y, &camera_loc.z) == 4 and cstring.strcmp(str, "loc") == 0, 
                     "Incorrect format for camera location, it should be 'loc x y z' " )
    return camera_loc
end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- Terra function to read the film location. This is an alternative way to represent camera aperture and rotation directly using film plane.
-- It is assumed here that the 3 points are in a plane. Ideally, they should have the same aspect ratio as the input height and width. 
-- If they do not have the same aspect ratio, then as obvious, the objects will look distorted.
terra read_film_loc(file_camera : &c.FILE, film_loc : &float)
    var str1: int8[512]
    var str2: int8[512]
    regentlib.assert(c.fscanf(file_camera, "%s %s %f %f %f\n", &str1, &str2, &film_loc[0], &film_loc[1], &film_loc[2]) == 5 and cstring.strcmp(str1, "film") == 0
                     and cstring.strcmp(str2, "tl") == 0, "Incorrect format for film location, it should be 'film tl x y z' ")
    regentlib.assert(c.fscanf(file_camera, "%s %s %f %f %f\n", &str1, &str2, &film_loc[3], &film_loc[4], &film_loc[5]) == 5 and cstring.strcmp(str1, "film") == 0
                     and cstring.strcmp(str2, "tr") == 0, "Incorrect format for film location, it should be 'film tr x y z' ")
    regentlib.assert(c.fscanf(file_camera, "%s %s %f %f %f\n", &str1, &str2, &film_loc[6], &film_loc[7], &film_loc[8]) == 5 and cstring.strcmp(str1, "film") == 0
                     and cstring.strcmp(str2, "bl") == 0, "Incorrect format for film location, it should be 'film bl x y z' ")
end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- This task is used to initialize the camera location, and the film plane, and objects
task initialize_camera_film_objects(filename_camera : int8[512], 
                                    film_plane : region(ispace(int2d), Point),
                                    filename_object : int8[512],
                                    r_objs : region(ispace(int1d), Object))
    where
       writes (film_plane.{x, y, z}, r_objs.{objtype, center.{x, y, z}, radius, diffuse_color.{r, g, b}, specular_color.{r, g, b}, specular_hardness, ior, transmission})
    do
       var film_loc : float[12]
       var file_camera = c.fopen(filename_camera, "rb")
       -- Read the camera location
       var camera_loc : Point = read_camera_loc(file_camera)
       -- Read the film location
       read_film_loc(file_camera, film_loc)

       -- Store the data of film location in the film plane 2 x 2 region
       for i = 0, 2 do
        for j = 0, 2 - i do
            film_plane[{i, j}].x = film_loc[6 * i + 3 * j]
            film_plane[{i, j}].y = film_loc[6 * i + 3 * j + 1]
            film_plane[{i, j}].z = film_loc[6 * i + 3 * j + 2]
        end
       end

       -- Read the objects
       var file_object = c.fopen(filename_object, "r")
       skip_header(file_object)
       for obj in r_objs do
          var obj_loc : float[13]
          var feature: int8[5][512]
          var objtype: int8[20]
          -- Read object lines in correct order
          regentlib.assert(c.fscanf(file_object, "%s %f %f %f %f %s %f %f %f %s %f %f %f %s %f %s %f %s %f\n",
                                    &objtype, &obj_loc[0], &obj_loc[1], &obj_loc[2], &obj_loc[3],
                                    &feature[0], &obj_loc[4], &obj_loc[5], &obj_loc[6],
                                    &feature[1], &obj_loc[7], &obj_loc[8], &obj_loc[9],
                                    &feature[2], &obj_loc[10], &feature[3], &obj_loc[11],  &feature[4], &obj_loc[12]) == 19
                                    and cstring.strcmp(feature[0], "d") == 0 and cstring.strcmp(feature[1], "s") == 0
                                    and cstring.strcmp(feature[2], "sh") == 0 and cstring.strcmp(feature[3], "ior") == 0
                                    and cstring.strcmp(feature[4], "t") == 0, 
                                    "Incorrect/Incomplete data in object file")
  
          -- Store the object characteristics in the Object element in the object region 
          obj.objtype = objtype    
          if cstring.strcmp(objtype, "sphere") == 0 then                        
            obj.center.x = obj_loc[0]
            obj.center.y = obj_loc[1]
            obj.center.z = obj_loc[2]
            obj.radius = obj_loc[3]
          end
          obj.diffuse_color.r = obj_loc[4]
          obj.diffuse_color.g = obj_loc[5]
          obj.diffuse_color.b = obj_loc[6]
          obj.specular_color.r = obj_loc[7]
          obj.specular_color.g = obj_loc[8]
          obj.specular_color.b = obj_loc[9]
          obj.specular_hardness = obj_loc[10]
          obj.ior = obj_loc[11]
          obj.transmission = obj_loc[12]

        end
       
        -- Return camera location
       return camera_loc
    end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- This task is used to initialize the light characteristics and the ambient color of the scene
task initialize_lights_and_ambient_color(filename_light : int8[512], 
                                         r_lights : region(ispace(int1d), Light))
    where
       writes (r_lights.{loc.{x, y, z}, color.{r, g, b}, energy})
    do
       -- Read the lights file
       var file_light = c.fopen(filename_light, "r")
       skip_header(file_light)
       var obj_loc : float[7]
       var type: int8[512]

       -- Read all lights
       for light in r_lights do
          regentlib.assert(c.fscanf(file_light, "%s %f %f %f %f %f %f %f\n",
                                    &type, &obj_loc[0], &obj_loc[1], &obj_loc[2], &obj_loc[3], &obj_loc[4], &obj_loc[5], &obj_loc[6]) == 8 
                                    and cstring.strcmp(type, "light") == 0, "Incorrect/Incomplete data in light file")
  
          light.loc.x = obj_loc[0]
          light.loc.y = obj_loc[1]
          light.loc.z = obj_loc[2]
          light.color.r = obj_loc[3]
          light.color.g = obj_loc[4]
          light.color.b = obj_loc[5]
          light.energy = obj_loc[6]
        end

        -- Read the ambient color of the scene from the file
        regentlib.assert(c.fscanf(file_light, "%s %f %f %f\n",
                                  &type, &obj_loc[0], &obj_loc[1], &obj_loc[2]) == 4 and cstring.strcmp(type, "ambient") == 0,
                                  "Incorrect/Incomplete data in light file")
        var ambient_color = Color{obj_loc[0], obj_loc[1], obj_loc[2]}
        return ambient_color
    end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- This task is used to initialize the first set of rays for the image.
-- The ray is simply defined from the location of camera to location of pixel. Location of pixel is found using linear interpolation 
-- from the film plane coordinates. The (0, 0)th coordinate will lie at the top left of the film plane. 
-- the (height, width)th coordinate will lie at the bottom left of the film plane.
task initialize_rays(r_image: region(ispace(int2d), Pixel), 
                     camera_loc: Point, 
                     film_plane: region(ispace(int2d), Point),
                     height: uint64,
                     width: uint64,
                     depth: uint64)
    where
        reads (film_plane.{x, y, z}), writes (r_image.{ray.{loc, dir, factor, depth}})
    do
        for i = 0, height do
            for j = 0, width do
                r_image[{i, j}].ray.dir.x = film_plane[{0, 0}].x
                r_image[{i, j}].ray.dir.y = film_plane[{0, 0}].y + j * 1.0 / width * (film_plane[{0, 1}].y - film_plane[{0, 0}].y)
                r_image[{i, j}].ray.dir.z = film_plane[{0, 0}].z + i * 1.0 / height * (film_plane[{1, 0}].z - film_plane[{0, 0}].z)
                r_image[{i, j}].ray.loc.x = camera_loc.x
                r_image[{i, j}].ray.loc.y = camera_loc.y
                r_image[{i, j}].ray.loc.z = camera_loc.z
                r_image[{i, j}].ray.factor = 1
                r_image[{i, j}].ray.depth = depth
            end
        end
    end
----------------------------------------------------------------------------------------------------------------------------------------------------------- 
-- Inline task for ray cast. This function finds the intersection of the ray with all the objects in the scene. Then, it returns the object with the
-- nearest intersection. We will return an intersection point field space, which will store details about the object it hit, the location of intersection
-- and the normal at the point of intersection.   
__demand(__inline)
task ray_cast(ray_dir: Vector,
              ray_loc: Point,
              r_objs: region(ispace(int1d), Object),
              num_objs: uint64)
    where
        reads (r_objs)
    do
        -- Start with some initial value for minimum di1
        var min_di1: float = 9999999.0
        var di1_idx: uint64

        for idx = 0, num_objs do
            -- Check the intersection of the ray with all objects. Find the minimum intersection
            var obj: Object = r_objs[idx]
            var di1: float = intersection(ray_loc, ray_dir, obj.center, obj.radius)
            if di1 < min_di1 then
                min_di1 = di1
                di1_idx = idx
            end
        end

        var int_point: IntersectionPoint
        if min_di1 == 9999999.0 then
            -- If no ray intersected the object
            int_point.has_hit = false
        else
            -- Otherwise update the intersection point parameters and return
            int_point.has_hit = true
            int_point.hit_idx = di1_idx
            int_point.hit_loc = plusPoint(ray_loc, vector_multc(ray_dir:normalized(), min_di1))
            int_point.hit_norm = get_vector(r_objs[di1_idx].center, int_point.hit_loc):normalized()
        end
        return int_point
    end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- This is the main function where we do the ray tracing for the image. For the input, we give the initial rays in r_image. We send the region of all
-- objects, lights, ambient color, number of objects and depth of the scene.
-- We develop a unique iterative DFS based ray tracing algorithm for the same.
task ray_trace(r_image: region(ispace(int2d), Pixel),
               r_objs: region(ispace(int1d), Object),
               r_lights: region(ispace(int1d), Light),
               ambient_color: Color,
               num_objs: uint64,
               depth: uint64)
    where 
        reads (r_objs, r_lights, r_image.ray), writes (r_image.color)
    do
        -- Create a stack that will be used for the DFS. The stack would only require depth + 1 nodes.
        var rays_stack = region(ispace(int1d, depth + 1), Ray)
        var ray : Ray
        var color: Color
        var curr_top: int
        var hit_obj: Object
        var hit_norm: Vector
        var no_light_hit: bool
        var ray_inside_obj: bool

        -- For each pixel in the image
        for pixel in r_image do
            -- Get the initial ray, set the color to 0, current top to 0, 0th element of rays stack to initial ray
            color = {0, 0, 0}
            curr_top = 0
            rays_stack[0] = pixel.ray
            -- Till the time we have elements available in our stack, we will continue the loop
            while curr_top >= 0 do
                -- Get the ray from the stack and normalize the ray
                ray = rays_stack[curr_top]
                ray.dir = ray.dir:normalized()
                curr_top -= 1
                -- Ray cast the ray on the scene to find the nearest intersection point 
                var int_point: IntersectionPoint = ray_cast(ray.dir, ray.loc, r_objs, num_objs)

                -- If the ray hits an object, then we move ahead, otherwise we do nothing and the color contribution is none
                if int_point.has_hit then
                    -- First, we check if the ray is inside the object or outside the object.
                    -- This is simply done by comparing the ray direction with the normal direction. If their dot product is positive, it means that the ray
                    -- is inside the object. If that is the case, we will reverse the direction of the normal for our computations.
                    ray_inside_obj = false
                    hit_norm = int_point.hit_norm
                    if dot(hit_norm, ray.dir) > 0 then
                        ray_inside_obj = true
                        hit_norm = Vector{-1 * hit_norm.x, -1 * hit_norm.y, -1 * hit_norm.z}
                    end
                    
                    -- Get the hit object
                    hit_obj = r_objs[int_point.hit_idx]
                    no_light_hit = true

                    -- Now, we have to get the contribution from each light separately.
                    for light in r_lights do
                        -- Get light vector from the hit location to the light location and normalize it.
                        var light_vec = get_vector(int_point.hit_loc, light.loc)
                        var light_dir = light_vec:normalized()

                        -- Use ray cast to find the intersection for the light ray.
                        var shadow_ray_int_point: IntersectionPoint = ray_cast(light_dir, plusPoint(int_point.hit_loc, vector_multc(hit_norm, 0.00001)), r_objs, num_objs)

                        -- If light did not hit any object, then that light will have an impact on the object.
                        if not shadow_ray_int_point.has_hit then
                            -- Light intensity = light color * energy / length^2
                            var light_intensity = color_multc(light.color, light.energy / light_vec:normsq())
                            
                            var light_dir_dot_hit_norm = dot(light_dir, hit_norm)
                            -- Diffuse shading
                            color = addColor(color, color_multc(mult_colors(light_intensity, hit_obj.diffuse_color), dot(light_dir, hit_norm) * ray.factor))
                            color = addColor(color, color_multc(mult_colors(light_intensity, hit_obj.specular_color), 
                                            c.pow(dot(hit_norm, minus(light_dir, ray.dir):normalized()), hit_obj.specular_hardness) * ray.factor))  

                            no_light_hit = false
                        end
                    end

                    -- If no light hit the pixel, shade it with ambient color.
                    if no_light_hit then
                        color = addColor(color, color_multc(mult_colors(hit_obj.diffuse_color, ambient_color), ray.factor))
                    end

                    -- If ray depth is greater than 0, we will add a reflected and transmitted ray into the stack
                    if ray.depth > 0 then
                        var dot_hit_norm_ray_dir = dot(hit_norm, ray.dir)
                        -- Use the IOR and cos theta to find fresnel's reflectivity
                        var R0 = c.pow((1 - hit_obj.ior) / (1 + hit_obj.ior), 2)
                        var cos_theta = -1 * dot_hit_norm_ray_dir
                        var reflectivity = R0 + (1 - R0) * c.pow(1 - cos_theta, 5)

                        -- Get the direction and location of the reflected ray. We add hit_norm * 0.00001 to prevent spurious self-occlusion.
                        var ray_reflect : Ray
                        ray_reflect.dir = plus(ray.dir, vector_multc(hit_norm, -2 * dot_hit_norm_ray_dir)):normalized()
                        ray_reflect.loc = plusPoint(int_point.hit_loc, vector_multc(hit_norm, 0.00001))
                        -- Factor for reflected ray is factor of parent ray multiplied by reflectivity
                        ray_reflect.factor = ray.factor * reflectivity
                        -- Depth for reflected ray is depth of parent ray - 1
                        ray_reflect.depth = ray.depth - 1

                        -- Add reflected ray to stack
                        rays_stack[curr_top + 1] = ray_reflect
                        curr_top = curr_top + 1

                        if hit_obj.transmission > 0 then
                            -- If object is transmissive, then add transmitted ray to solution
                            var ior_ratio = hit_obj.ior
                            if not ray_inside_obj then
                                ior_ratio = 1 / hit_obj.ior
                            end

                            -- Find the square root term (used to check for total internal reflection)
                            var sqrt_term = 1 - ior_ratio * ior_ratio * (1 - dot_hit_norm_ray_dir * dot_hit_norm_ray_dir)
                            if sqrt_term > 0 then
                                -- If there is a transmitted ray, which is when there is no total internal reflection, then add a transmitted ray
                                var ray_transmit : Ray

                                -- Get the direction and location of the transmitted ray. We add hit_norm * 0.00001 to prevent spurious self-occlusion.
                                ray_transmit.dir = plus(vector_multc(ray.dir, ior_ratio), vector_multc(hit_norm, -1 * (ior_ratio * dot_hit_norm_ray_dir + cmath.sqrt(sqrt_term))))
                                ray_transmit.loc = plusPoint(int_point.hit_loc, vector_multc(hit_norm, -0.00001))
                                -- Factor for transmitted ray is defined by factor of parent ray multiplied by transmissivity, which is equal to (1 - reflectivity) * transmission
                                ray_transmit.factor = ray.factor * (1 - reflectivity) * hit_obj.transmission
                                -- Depth for transmitted ray is depth of parent ray - 1
                                ray_transmit.depth = ray.depth - 1

                                -- Add transmitted ray to stack
                                rays_stack[curr_top + 1] = ray_transmit
                                curr_top = curr_top + 1
                            end
                        end
                    end              
                end
                -- Continue looping in DFS
            end

            -- Color's R/G/B component might have gone greater than 1. In that case, we scale down all components so that max component remains 1.
            var max_comp = max(max(color.r, color.g), color.b)
            if max_comp > 1 then
                color = Color{color.r / max_comp, color.g / max_comp, color.b / max_comp}
            end
            -- Pixel color will be integer color
            pixel.color = {255 * color.r, 255 * color.g, 255 * color.b}
        end
    end
----------------------------------------------------------------------------------------------------------------------------------------------------------- 
-- Task to save the rendered image on the given output location
task save_render(r_image : region(ispace(int2d), Pixel),
                filename : rawstring)
where
  reads(r_image.color)
do
    ray_trace_util.save_render(filename,
                     __physical(r_image.color),
                     __fields(r_image.color),
                     r_image.bounds)
end
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- Top level Task
task toplevel()
    -- Initialize the ray trace config
    var config : RayTraceConfig
    config:initialize_from_command()

    -- Create and initialize the regions of lights, objects, film plane
    var film_plane = region(ispace(int2d, {2, 2}), Point)
    var r_objs = region(ispace(int1d, config.num_objs), Object)
    var r_lights = region(ispace(int1d, config.num_lights), Light)
    var camera_loc : Point = initialize_camera_film_objects(config.filename_camera, film_plane, config.filename_object, r_objs)
    var ambient_color: Color = initialize_lights_and_ambient_color(config.filename_light, r_lights)

    -- Create image and initialize the rays based upon the height, width, camera location and film plane location
    var r_image = region(ispace(int2d, {config.height, config.width}), Pixel)
    initialize_rays(r_image, camera_loc, film_plane, config.height, config.width, config.depth)

    -- Partition the image into equal partitions
    var colors = ispace(int1d, config.parallelism)
    var image_partition = partition(equal, r_image, colors)

    var ts_start = c.legion_get_current_time_in_micros()
    
    for color in colors do
        -- Run ray trace for each partition separately
        ray_trace(image_partition[color], r_objs, r_lights, ambient_color, config.num_objs, config.depth)
    end
    __fence(__execution, __block)

    var ts_stop = c.legion_get_current_time_in_micros()
    c.printf("Ray Trace Complete in %.4f sec.\n", (ts_stop - ts_start) * 1e-6)

    -- Save the rendered image
    save_render(r_image, config.filename_out)
end

regentlib.start(toplevel)