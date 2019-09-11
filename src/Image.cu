#include "Image.cuh"

__device__ __host__ ssrlcv::Image::Camera::Camera(){
  this->cam_vec = {0.0f,0.0f,0.0f};
  this->cam_pos = {0.0f,0.0f,0.0f};
  this->fov = 0;
  this->foc = 0;
  this->dpix = {0.0f,0.0f};
  this->size = {0,0};
}
__device__ __host__ ssrlcv::Image::Camera::Camera(uint2 size){
  this->cam_vec = {0.0f,0.0f,0.0f};
  this->cam_pos = {0.0f,0.0f,0.0f};
  this->fov = 0;
  this->foc = 0;
  this->dpix = {0.0f,0.0f};
  this->size = {0,0};
}
__device__ __host__ ssrlcv::Image::Camera::Camera(uint2 size, float3 cam_pos, float3 camp_dir){
  this->cam_pos = cam_pos;
  this->cam_vec = cam_vec;
  this->fov = 0;
  this->foc = 0;
  this->dpix = {0.0f,0.0f};
  this->size = size;
}

ssrlcv::Image::Image(){
  this->id = -1;
  this->filePath = "n/a";
}
ssrlcv::Image::Image(std::string filePath, int id){
  this->filePath = filePath;
  this->id = id;
  this->colorDepth = 1;
  unsigned char* pixels_host = readPNG(filePath.c_str(), this->size.y, this->size.x, this->colorDepth);
  this->camera.size = this->size;
  this->pixels = new Unity<unsigned char>(pixels_host,this->size.y*this->size.x*this->colorDepth,cpu);
}
ssrlcv::Image::Image(std::string filePath, unsigned int convertColorDepthTo, int id){
  this->filePath = filePath;
  this->id = id;
  this->colorDepth = 1;
  unsigned char* pixels_host = readPNG(filePath.c_str(), this->size.y, this->size.x, this->colorDepth);
  this->camera.size = this->size;
  this->pixels = new Unity<unsigned char>(pixels_host,this->size.y*this->size.x*this->colorDepth,cpu);
  if(convertColorDepthTo == 1){
    convertToBW(this->pixels, this->colorDepth);
    this->colorDepth = 1;
  }
  else if(convertColorDepthTo != 0){
    std::cerr<<"ERROR: Image() does not currently support conversion to anything but BW"<<std::endl;
    exit(-1);
  }
}

ssrlcv::Image::~Image(){
  if(this->pixels != nullptr){
    delete this->pixels;
  }
}

void ssrlcv::Image::convertColorDepthTo(unsigned int colorDepth){
  std::cout<<"Converting pixel depth to "<<colorDepth<<" from "<<this->colorDepth<<std::endl;
  if(colorDepth == 1){
    convertToBW(this->pixels,this->colorDepth);
    this->colorDepth = 1;
  }
  else if (colorDepth == 3){
    convertToRGB(this->pixels,this->colorDepth);
    this->colorDepth = 3;
  }
  else{
    std::cerr<<colorDepth<<" is currently not supported in convertColorDepthTo"<<std::endl;
    exit(-1);
  }
}
ssrlcv::Unity<int2>* ssrlcv::Image::getPixelGradients(){
  return generatePixelGradients(this->size,this->pixels);
}
void ssrlcv::Image::alterSize(int binDepth){
  if(binDepth <= 0){
    std::cerr<<"Image::alterSize does not currently support upsampling"<<std::endl;
    exit(0);
  }
  MemoryState origin = this->pixels->state;
  if(origin == cpu || this->pixels->fore == cpu) this->pixels->transferMemoryTo(gpu);

  Unity<unsigned char>* alteredPixels = bin(this->size,this->colorDepth,this->pixels);
  delete this->pixels;
  this->pixels = alteredPixels;
  this->size.x /= pow(2,binDepth);
  this->size.y /= pow(2,binDepth);
  this->camera.size = size;


  this->pixels->fore = gpu;
  if(origin == cpu) this->pixels->setMemoryState(cpu);
}


ssrlcv::Unity<int2>* ssrlcv::generatePixelGradients(uint2 imageSize, Unity<unsigned char>* pixels){
  MemoryState origin = pixels->state;
  if(origin == cpu || pixels->fore == cpu){
    pixels->transferMemoryTo(gpu);
  }
  int2* gradients_device = nullptr;
  CudaSafeCall(cudaMalloc((void**)&gradients_device,pixels->numElements*sizeof(int2)));
  dim3 grid = {1,1,1};
  dim3 block = {1,1,1};
  getFlatGridBlock(pixels->numElements,grid,block);
  calculatePixelGradients<<<grid,block>>>(imageSize,pixels->device,gradients_device);
  CudaCheckError();

  if(origin == cpu) pixels->setMemoryState(cpu);

  return new Unity<int2>(gradients_device,pixels->numElements,gpu);
}
ssrlcv::Unity<unsigned char>* ssrlcv::bin(uint2 imageSize, unsigned int colorDepth, Unity<unsigned char>* pixels){
  MemoryState origin = pixels->state;

  if(origin == cpu || pixels->fore != gpu){
    pixels->transferMemoryTo(gpu);
  }
  unsigned char* binnedImage_device = nullptr;

  CudaSafeCall(cudaMalloc((void**)&binnedImage_device,(pixels->numElements/4)*colorDepth*sizeof(unsigned char)));
  binImage<<<{(imageSize.x/32)+1,(imageSize.y/32)+1,1},{32,32,1}>>>(imageSize,colorDepth,pixels->device,binnedImage_device);
  CudaCheckError();

  if(origin == cpu){
    pixels->setMemoryState(cpu);
  }

  Unity<unsigned char>* binnedImage = new Unity<unsigned char>(binnedImage_device, colorDepth*pixels->numElements/4, gpu);
  binnedImage->transferMemoryTo(cpu);

  return binnedImage;
}
ssrlcv::Unity<unsigned char>* ssrlcv::convolve(uint2 imageSize, Unity<unsigned char>* pixels, unsigned int colorDepth, int2 kernelSize, float* kernel){
  if(kernelSize.x%2 == 0 || kernelSize.y%2 == 0){
    std::cerr<<"ERROR kernel for image convolution must have an odd dimension"<<std::endl;
    exit(-1);
  }
  MemoryState origin = pixels->state;
  if(origin == cpu) pixels->transferMemoryTo(gpu);
  Unity<float>* convolvedImage = new Unity<float>(nullptr,imageSize.x*imageSize.y*colorDepth,gpu);
  float* kernel_device = nullptr;
  CudaSafeCall(cudaMalloc((void**)&kernel_device,kernelSize.x*kernelSize.y*sizeof(float)));
  CudaSafeCall(cudaMemcpy(kernel_device,kernel,kernelSize.x*kernelSize.y*sizeof(float),cudaMemcpyHostToDevice));
  dim3 grid = {(imageSize.x/32)+1,(imageSize.y/32)+1,colorDepth};
  dim3 block = {32,32,1};
  float2 minMax = {FLT_MAX,-FLT_MAX};
  float* min = nullptr;
  CudaSafeCall(cudaMalloc((void**)&min, sizeof(float)));
  CudaSafeCall(cudaMemcpy(min, &minMax.x,sizeof(float),cudaMemcpyHostToDevice));
  float* max = nullptr;
  CudaSafeCall(cudaMalloc((void**)&max, sizeof(float)));
  CudaSafeCall(cudaMemcpy(max, &minMax.y,sizeof(float),cudaMemcpyHostToDevice));

  convolveImage<<<grid,block>>>(imageSize, pixels->device, colorDepth, kernelSize, kernel_device, convolvedImage->device,min,max);
  cudaDeviceSynchronize();
  CudaCheckError();

  grid = {1,1,1};
  block = {1,1,1};
  getFlatGridBlock(imageSize.x*imageSize.y*colorDepth,grid,block);

  Unity<unsigned char>* convertedImage = new Unity<unsigned char>(nullptr,imageSize.x*imageSize.y*colorDepth,gpu);
  convertToCharImage<<<grid,block>>>(imageSize.x*imageSize.y*colorDepth,convertedImage->device, convolvedImage->device, min, max);
  CudaCheckError();
  delete convolvedImage;
  CudaSafeCall(cudaFree(min));
  CudaSafeCall(cudaFree(max));
  CudaSafeCall(cudaFree(kernel_device));

  if(origin == cpu) pixels->setMemoryState(cpu);
  return convertedImage;
}

void ssrlcv::convertToBW(Unity<unsigned char>* pixels, unsigned int colorDepth){
  if(colorDepth == 1){
    std::cout<<"Pixels are already bw"<<std::endl;
    return;
  }

  MemoryState origin = pixels->state;
  pixels->transferMemoryTo(gpu);

  unsigned int numPixels = (pixels->numElements/colorDepth);

  unsigned char* bwPixels_device;
  CudaSafeCall(cudaMalloc((void**)&bwPixels_device, numPixels*sizeof(unsigned char)));

  dim3 grid;
  dim3 block;
  getFlatGridBlock(numPixels, grid, block);
  generateBW<<<grid,block>>>(numPixels, colorDepth, pixels->device, bwPixels_device);
  CudaCheckError();

  pixels->setData(bwPixels_device, numPixels, gpu);
  pixels->setMemoryState(origin);
}
void ssrlcv::convertToRGB(Unity<unsigned char>* pixels, unsigned int colorDepth){
  if(colorDepth == 3){
    std::cout<<"Pixels are already rgb"<<std::endl;
    return;
  }

  MemoryState origin = pixels->state;
  pixels->transferMemoryTo(gpu);

  unsigned int numPixels = (pixels->numElements/colorDepth);

  unsigned char* rgbPixels_device;
  CudaSafeCall(cudaMalloc((void**)&rgbPixels_device, numPixels*3*sizeof(unsigned char)));

  dim3 grid;
  dim3 block;
  getFlatGridBlock(numPixels, grid, block);
  generateRGB<<<grid,block>>>(numPixels, colorDepth, pixels->device, rgbPixels_device);
  CudaCheckError();

  pixels->setData(rgbPixels_device, 3*numPixels, gpu);
  pixels->setMemoryState(origin);
}


void ssrlcv::calcFundamentalMatrix_2View(Image* query, Image* target, float3 *F){
  if(query->camera.fov != target->camera.fov || query->camera.foc != target->camera.foc){
    std::cout<<"ERROR calculating fundamental matrix for 2view needs to bet taken with same camera (foc&fov are same)"<<std::endl;
    exit(-1);
  }
  float angle1;
  if(abs(query->camera.cam_vec.z) < .00001) {
    if(query->camera.cam_vec.y > 0)  angle1 = PI/2;
    else       angle1 = -1*PI/2;
  }
  else {
    angle1 = atan(query->camera.cam_vec.y / query->camera.cam_vec.z);
    if(query->camera.cam_vec.z<0 && query->camera.cam_vec.y>=0) {
      angle1 += PI;
    }
    if(query->camera.cam_vec.z<0 && query->camera.cam_vec.y<0) {
      angle1 -= PI;
    }
  }
  float3 A1[3] = {
    {1, 0, 0},
    {0, cos(angle1), -sin(angle1)},
    {0, sin(angle1), cos(angle1)}
  };

  float3 temp = multiply3x3x1(A1, query->camera.cam_vec);

  float angle2 = 0.0f;
  if(abs(temp.z) < .00001) {
    if(temp.x <= 0)  angle1 = PI/2;
    else       angle1 = -1*PI/2;
  }
  else {
    angle2 = atan(-1*temp.x / temp.z);
    if(temp.z<0 && temp.x<0) {
      angle1 += PI;
    }
    if(temp.z<0 && temp.x>0) {
      angle2 -= PI;
    }
  }
  float3 B1[3] = {
    {cos(angle2), 0, sin(angle2)},
    {0, 1, 0},
    {-sin(angle2), 0, cos(angle2)}
  };

  float3 temp2 = multiply3x3x1(B1, temp);
  float3 rot1[3];
  multiply3x3(B1, A1, rot1);
  float3 rot1Transpose[3];
  transpose3x3(rot1,rot1Transpose);
  temp = multiply3x3x1(rot1Transpose, temp2);

  angle1 = 0.0f;
  if(abs(target->camera.cam_vec.z) < .00001) {
    if(target->camera.cam_vec.y > 0)  angle1 = PI/2;
    else       angle1 = -1*PI/2;
  }
  else {
    angle1 = atan(target->camera.cam_vec.y / target->camera.cam_vec.z);
    if(target->camera.cam_vec.z<0 && target->camera.cam_vec.y>=0) {
      angle1 += PI;
    }
    if(target->camera.cam_vec.z<0 && target->camera.cam_vec.y<0) {
      angle1 -= PI;
    }
  }
  float3 A2[3] = {
    {1, 0, 0},
    {0, cos(angle1), -sin(angle1)},
    {0, sin(angle1), cos(angle1)}
  };
  temp2 = multiply3x3x1(A2, target->camera.cam_vec);

  angle2 = 0.0f;
  if(abs(temp2.z) < .00001) {
    if(temp2.x <= 0)  angle1 = PI/2;
    else       angle1 = -1*PI/2;
  }
  else {
    angle2 = atan(-1*temp2.x / temp2.z);
    if(temp2.z<0 && temp2.x<0) {
      angle1 += PI;
    }
    if(temp2.z<0 && temp2.x>0) {
      angle2 -= PI;
    }
  }
  float3 B2[3] = {
    {cos(angle2), 0, sin(angle2)},
    {0, 1, 0},
    {-sin(angle2), 0, cos(angle2)}
  };

  temp = multiply3x3x1(B2, temp2);

  float3 rot2[3];
  multiply3x3(B2, A2, rot2);
  float3 rot2Transpose[3];
  transpose3x3(rot2, rot2Transpose);

  temp2 = multiply3x3x1(rot2Transpose, temp);

  float3 K[3] = {
    {query->camera.foc/query->camera.dpix.x, 0, ((float)query->size.x)/2.0f},
    {0, query->camera.foc/query->camera.dpix.y, ((float)query->size.y)/2.0f},
    {0, 0, 1}
  };
  float3 K_inv[3];
  inverse3x3(K,K_inv);
  float3 K_invTranspose[3];
  transpose3x3(K_inv,K_invTranspose);

  float3 R[3];
  multiply3x3(rot2Transpose, rot1, R);
  float3 S[3] = {
    {0, query->camera.cam_pos.z - target->camera.cam_pos.z, target->camera.cam_pos.y - query->camera.cam_pos.y},
    {query->camera.cam_pos.z - target->camera.cam_pos.z,0, query->camera.cam_pos.x - target->camera.cam_pos.x},
    {query->camera.cam_pos.y - target->camera.cam_pos.y, target->camera.cam_pos.x - query->camera.cam_pos.x, 0}
  };
  float3 E[3];;
  multiply3x3(R,S,E);
  float3 tempF[3];
  multiply3x3(K_invTranspose, E,tempF);
  multiply3x3(tempF, K_inv, F);
  std::cout << std::endl <<"between image "<<query->id<<" and "<<target->id
  <<" the final fundamental matrix result is: " << std::endl;
  for(int r = 0; r < 3; ++r) {
    std::cout << F[r].x << "  " << F[r].y << " "<<  F[r].z << std::endl;
  }
  std::cout<<std::endl;
}
void ssrlcv::get_cam_params2view(Image* cam1, Image* cam2, std::string infile){
  std::ifstream input(infile);
  std::string line;
  float res = 0.0f;
  while(std::getline(input, line)) {
    std::istringstream iss(line);
    std::string param;
    float arg1;
    float arg2;
    float arg3;
    iss >> param >> arg1;
    if(param.compare("foc") == 0) {
      cam1->camera.foc = arg1;
      cam2->camera.foc = arg1;
    }
    else if(param.compare("fov") == 0) {
      cam1->camera.fov = arg1;
      cam2->camera.fov = arg1;
    }
    else if(param.compare("res") == 0) {
      res = arg1;
    }
    else if(param.compare("cam1C") == 0) {
      iss >> arg2 >> arg3;
      cam1->camera.cam_pos.x = arg1;
      cam1->camera.cam_pos.y = arg2;
      cam1->camera.cam_pos.z = arg3;
    }
    else if(param.compare("cam1V") == 0) {
      iss >> arg2 >> arg3;
      cam1->camera.cam_vec.x = arg1;
      cam1->camera.cam_vec.y = arg2;
      cam1->camera.cam_vec.z = arg3;
    }
    else if(param.compare("cam2C") == 0) {
      iss >> arg2 >> arg3;
      cam2->camera.cam_pos.x = arg1;
      cam2->camera.cam_pos.y = arg2;
      cam2->camera.cam_pos.z = arg3;
    }
    else if(param.compare("cam2V") == 0) {
      iss >> arg2 >> arg3;
      cam2->camera.cam_vec.x = arg1;
      cam2->camera.cam_vec.y = arg2;
      cam2->camera.cam_vec.z = arg3;
    }
  }

  cam1->camera.dpix = {cam1->camera.foc*tan(cam1->camera.fov/2)/(cam1->size.x/2),
    cam1->camera.foc*tan(cam1->camera.fov/2)/(cam1->size.y/2)};
  cam2->camera.dpix = {cam2->camera.foc*tan(cam2->camera.fov/2)/(cam2->size.x/2),
    cam2->camera.foc*tan(cam2->camera.fov/2)/(cam2->size.y/2)};
}


__device__ __forceinline__ float ssrlcv::atomicMinFloat (float * addr, float value){
  float old;
  old = (value >= 0) ? __int_as_float(atomicMin((int *)addr, __float_as_int(value))) :
    __uint_as_float(atomicMax((unsigned int *)addr, __float_as_uint(value)));
  return old;
}
__device__ __forceinline__ float ssrlcv::atomicMaxFloat (float * addr, float value){
  float old;
  old = (value >= 0) ? __int_as_float(atomicMax((int *)addr, __float_as_int(value))) :
    __uint_as_float(atomicMin((unsigned int *)addr, __float_as_uint(value)));
  return old;
}
__device__ __forceinline__ unsigned long ssrlcv::getGlobalIdx_2D_1D(){
  unsigned long blockId = blockIdx.y * gridDim.x + blockIdx.x;
  unsigned long threadId = blockId * blockDim.x + threadIdx.x;
  return threadId;
}
__device__ __forceinline__ unsigned char ssrlcv::bwaToBW(const uchar2 &color){
  return (1-color.y)*color.x + color.y*color.x;
}
__device__ __forceinline__ unsigned char ssrlcv::rgbToBW(const uchar3 &color){
  return (color.x/4) + (color.y/2) + (color.z/4);
}
__device__ __forceinline__ unsigned char ssrlcv::rgbaToBW(const uchar4 &color){
  return rgbToBW(rgbaToRGB(color));
}
__device__ __forceinline__ uchar3 ssrlcv::bwToRGB(const unsigned char &color){
  int colorTemp = (int) color*10;
  return {(unsigned char)colorTemp/4,(unsigned char)colorTemp/2,(unsigned char)colorTemp/4};
}
__device__ __forceinline__ uchar3 ssrlcv::bwaToRGB(const uchar2 &color){
  return {color.x,color.y,(color.x/3)*2 + (color.y/3)};
}
__device__ __forceinline__ uchar3 ssrlcv::rgbaToRGB(const uchar4 &color){
  return {
    (1-color.w)*color.x + color.w*color.x,
    (1-color.w)*color.y + color.w*color.y,
    (1-color.w)*color.z + color.w*color.z,
  };
}




__global__ void ssrlcv::generateBW(int numPixels, unsigned int colorDepth, unsigned char* colorPixels, unsigned char* pixels){
  unsigned long globalID = getGlobalIdx_2D_1D();
  if(globalID < numPixels){
    int numValues = colorDepth;
    switch(numValues){
      case 2:
        pixels[globalID] = bwaToBW({colorPixels[globalID*numValues],colorPixels[globalID*numValues + 1]});
        break;
      case 3:
        pixels[globalID] = rgbToBW({colorPixels[globalID*numValues],colorPixels[globalID*numValues + 1], colorPixels[globalID*numValues + 2]});
        break;
      case 4:
        pixels[globalID] = rgbaToBW({colorPixels[globalID*numValues],colorPixels[globalID*numValues + 1], colorPixels[globalID*numValues + 2], colorPixels[globalID*numValues + 3]});
        break;
      default:
        printf("ERROR colorDepth of %u is not supported\n",numValues);
        asm("trap;");
    }
  }
}
__global__ void ssrlcv::generateRGB(int numPixels, unsigned int colorDepth, unsigned char* colorPixels, unsigned char* pixels){
  unsigned long globalID = getGlobalIdx_2D_1D();
  if(globalID < numPixels){
    int numValues = colorDepth;
    uchar3 value;
    switch(numValues){
      case 1:
        value = bwToRGB(colorPixels[globalID]);
        break;
      case 2:
        value = bwaToRGB({colorPixels[globalID*numValues],colorPixels[globalID*numValues + 1]});
        break;
      case 4:
        value = rgbaToRGB({colorPixels[globalID*numValues],colorPixels[globalID*numValues + 1], colorPixels[globalID*numValues + 2], colorPixels[globalID*numValues + 3]});
        break;
      default:
        printf("ERROR colorDepth of %u is not supported\n",numValues);
        asm("trap;");
    }
    pixels[globalID*3] = value.x;
    pixels[globalID*3 + 1] = value.y;
    pixels[globalID*3 + 2] = value.z;
  }
}

__global__ void ssrlcv::binImage(uint2 imageSize, unsigned int colorDepth, unsigned char* pixels, unsigned char* binnedImage){
  unsigned int x = blockIdx.x*blockDim.x + threadIdx.x;
  unsigned int y = blockIdx.y*blockDim.y + threadIdx.y;
  if(x < imageSize.x/2 && y < imageSize.y/2){
    for(int d = 0; d < colorDepth; ++d){
      float sumPix = pixels[y*colorDepth*2*imageSize.x + x*2*colorDepth + d] +
      pixels[(y + 1)*colorDepth*2*imageSize.x + x*2*colorDepth + d] +
      pixels[y*colorDepth*2*imageSize.x + (x+1)*2*colorDepth + d] +
      pixels[(y+1)*colorDepth*2*imageSize.x + (x+1)*2*colorDepth + d];
      binnedImage[y*colorDepth*(imageSize.x/2) + x*colorDepth + d] = (unsigned char) (sumPix/4);
    }
  }
}

__global__ void ssrlcv::convolveImage(uint2 imageSize, unsigned char* pixels, unsigned int colorDepth, int2 kernelSize, float* kernel, float* convolvedImage, float* min, float* max){
  unsigned int x = blockIdx.x*blockDim.x + threadIdx.x;
  unsigned int y = blockIdx.y*blockDim.y + threadIdx.y;
  unsigned int color = blockIdx.z*blockDim.z + threadIdx.z;
  if(x < imageSize.x && y < imageSize.y){
    if(x + (kernelSize.x/2) >= imageSize.x || x < kernelSize.x/2 || y + (kernelSize.y/2) >= imageSize.y || y < kernelSize.y/2){
      convolvedImage[(y*imageSize.x + x)*colorDepth + color] = 0;
    }
    else{
      float sum = 0.0f;
      for(int kx = -kernelSize.x/2; kx <= kernelSize.x/2; ++kx){
        for(int ky = -kernelSize.y/2; ky <= kernelSize.y/2; ++ky){
          sum += ((float)pixels[((y+ky)*imageSize.x + (x+kx))*colorDepth + color])*kernel[(ky+(kernelSize.y/2))*kernelSize.x + (kx+(kernelSize.x/2))];
        }
      }
      sum /= (kernelSize.x*kernelSize.y);
      atomicMaxFloat(max,sum);
      atomicMinFloat(min,sum);
      convolvedImage[(y*imageSize.x + x)*colorDepth + color] = sum;
    }
  }
}

__global__ void ssrlcv::convertToCharImage(unsigned int numPixels, unsigned char* pixels, float* fltPixels, float* min, float* max){
  unsigned long globalID = getGlobalIdx_2D_1D();
  if(globalID < numPixels){
    pixels[globalID] = (unsigned char) 255.0f*((fltPixels[globalID]-*min)/(*max-*min));
  }
}

__global__ void ssrlcv::calculatePixelGradients(uint2 imageSize, unsigned char* pixels, int2* gradients){
  unsigned long globalID = (blockIdx.y* gridDim.x+ blockIdx.x)*blockDim.x + threadIdx.x;
  if(globalID < imageSize.x*imageSize.y){
    uint2 loc = {globalID%imageSize.x,globalID/imageSize.x};
    if(loc.x == 0 || loc.x == imageSize.x - 1 || loc.y == 0 || loc.y == imageSize.y - 1){
      gradients[globalID] = {0,0};
    }
    else{
      gradients[globalID].x = (int)pixels[loc.y*imageSize.x + loc.x + 1] - (int)pixels[loc.y*imageSize.x + loc.x - 1];
      gradients[globalID].y = (int)pixels[(loc.y + 1)*imageSize.x + loc.x] - (int)pixels[(loc.y - 1)*imageSize.x + loc.x];
    }
  }
}
