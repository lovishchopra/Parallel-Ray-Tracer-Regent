import "regent"

local c = regentlib.c

struct RayTraceConfig
{
  filename_camera : int8[512];
  filename_object : int8[512];
  filename_light  : int8[512];
  num_objs        : uint64;
  num_lights      : uint64;
  height          : uint64;
  width           : uint64;
  depth           : uint64;
  filename_out    : rawstring;
  parallelism     : uint32;
}

local cstring = terralib.includec("string.h")

terra print_usage_and_abort()
  c.printf("Usage: regent.py edge.rg [OPTIONS]\n")
  c.printf("OPTIONS\n")
  c.printf("  -h            : Print the usage and exit.\n")
  c.printf("  -c {file}     : Camera file.\n")
  c.printf("  -l {file}     : Lights file.\n")
  c.printf("  -i {file}     : Input Objects file.\n")
  c.printf("  -height {value}     : Set height resolution of image to {value} pixels.\n")
  c.printf("  -width {value}     : Set width resolution of image to {value} pixels.\n")
  c.printf("  -d {value}     : Set depth of ray tracing to {value}.\n")
  c.printf("  -o {file}      : File to store output.\n")
  c.printf("  -p {value}      : Set the number of parallel tasks to {value}\n")
  c.abort()
end

terra RayTraceConfig:initialize_from_command()
  var filename_object_given = false
  cstring.strcpy(self.filename_camera, "camera.txt")
  self.filename_out = "output.png"
  self.height = 1080
  self.width = 1920
  self.depth = 4
  self.parallelism = 1

  var args = c.legion_runtime_get_input_args()
  var i = 1
  while i < args.argc do
    if cstring.strcmp(args.argv[i], "-h") == 0 then
      print_usage_and_abort()
    elseif cstring.strcmp(args.argv[i], "-c") == 0 then
      i = i + 1
      cstring.strcpy(self.filename_camera, args.argv[i]) 
    elseif cstring.strcmp(args.argv[i], "-o") == 0 then
      i = i + 1
      self.filename_out = args.argv[i]
    elseif cstring.strcmp(args.argv[i], "-i") == 0 then
      i = i + 1
      cstring.strcpy(self.filename_object, args.argv[i])  
      filename_object_given = true
      var file = c.fopen(args.argv[i], "rb")
      if file == nil then
        c.printf("File '%s' doesn't exist!\n", args.argv[i])
        c.abort()
      end
      c.fscanf(file, "%llu\n", &self.num_objs)
      c.fclose(file)
    elseif cstring.strcmp(args.argv[i], "-l") == 0 then
      i = i + 1
      cstring.strcpy(self.filename_light, args.argv[i])  
      var file = c.fopen(args.argv[i], "rb")
      if file == nil then
        c.printf("File '%s' doesn't exist!\n", args.argv[i])
        c.abort()
      end
      c.fscanf(file, "%llu\n", &self.num_lights)
      c.fclose(file)
    elseif cstring.strcmp(args.argv[i], "-height") == 0 then
      i = i + 1
      self.height = c.atoi(args.argv[i]) 
    elseif cstring.strcmp(args.argv[i], "-width") == 0 then
      i = i + 1
      self.width = c.atoi(args.argv[i]) 
    elseif cstring.strcmp(args.argv[i], "-p") == 0 then
      i = i + 1
      self.parallelism = c.atoi(args.argv[i])
    end
    i = i + 1
  end
  if not filename_object_given then
    c.printf("Input object file must be given!\n\n")
    print_usage_and_abort()
  end
end

return RayTraceConfig
