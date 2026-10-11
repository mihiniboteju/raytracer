#pragma once

#include "common.hpp"
#include "vec.hpp"

#include <random>

#ifdef OPENMP
#include <omp.h>
#endif

using namespace raytracer;

// Utility functions for random number generation and sampling.
namespace raytracer::random {

inline std::mt19937& generator() {
  thread_local std::mt19937 engine([] {
    unsigned int seed = 0x9e3779b9u;
#ifdef OPENMP
    seed += static_cast<unsigned int>(omp_get_thread_num());
#endif
    return seed;
  }());
  return engine;
}

// returns a random real in [0,1).
inline double rand() {
  return std::generate_canonical<double, std::numeric_limits<double>::digits>(generator());
}

// returns a random real in [min,max).
inline double rand(double min, double max) {
  return min + (max-min)*rand();
}

// returns a random integer in [min,max].
inline double rand_int(int min, int max) {
  return std::uniform_int_distribution<int>(min, max)(generator());
}

// returns a random sample in the quad defined by the point p and the vectors u and v
inline Point sample_quad(Point p, Vec u, Vec v) {
  return p + rand()*u + rand()*v;
}

// returns a stratified sample in the quad defined by the point p and the vectors u and v
// cell is the index of the grid cell in the stratified sampling grid
// sqrt_n_samples is the squared root of total number of samples in the grid
// for pixels, sqrt_n_samples = sqrt(samples_per_pixel)
inline Point sample_quad_stratified(Point p, Vec u, Vec v, int cell, int sqrt_n_samples) {
  int n_samples = sqrt_n_samples*sqrt_n_samples;
  int i = cell / n_samples;
  int j = cell % n_samples;
  double u_offset = (i + rand()) / sqrt_n_samples;
  double v_offset = (j + rand()) / sqrt_n_samples;
  return p + (u * u_offset) + (v * v_offset);
}

// returns a random sample in the triangle defined by the point a and the vectors u and v
inline Point sample_triangle(Point a, Vec u, Vec v) {
  double alpha = rand();
  double beta = rand();
  if (alpha + beta > 1) {
    alpha = 1 - alpha;
    beta = 1 - beta;
  }
  return a + alpha*u + beta*v;
}

// returns a random sample in the disk of radius r at z=0
inline Point sample_disk(double r) {
  double phi = 2 * M_PI * rand();   // phi = random in [0, 2pi)
  return Point(r*cos(phi), r*sin(phi), 0);
}

// returns a sample in the given CDF
inline int sample_cdf(const std::vector<double>& cdf) {
  double r = rand();
  for (int i = 0; i < (int)cdf.size(); i++) {
    if (cdf[i] > r) return i;
  }
  return -1; // should never happen
}


/////// VECTOR SAMPLING ///////


// returns a random Vec in [0,1)^3.
inline Vec vec() {
  return Vec(random::rand(), random::rand(), random::rand());
}

// returns a random Vec in [min,max)^3.
inline Vec vec(double min, double max) {
  return Vec(random::rand(min, max), random::rand(min, max), random::rand(min, max));
}

// returns a random unit vector (a point on the surface of the unit sphere).
inline Vec sample_sphere_uniform() {
  double z   = random::rand(-1, 1);     // z   = random in [-1, 1)
  double phi = random::rand(0, 2*M_PI); // phi = random in [0, 2pi)
  double r = std::sqrt(1 - z*z);
  double x = r*cos(phi);                 // x = sqrt(1 - z*z) * cos(phi)
  double y = r*sin(phi);                 // y = sqrt(1 - z*z) * sin(phi)
  return Vec(x, y, z);                   // already unitary
}

// returns a random sample in the surface of the sphere centered at c with radius r
inline Vec sample_sphere_uniform(Point c, double r) {
  return c + r*sample_sphere_uniform();
}

// Returns an uniform sampled unit vector in the hemisphere of the z-axis.
// The returned vector is always in the hemisphere of the normal vector.
// This is uniform in the hemisphere of the z-axis,
// but not uniform in the hemisphere of the normal vector.
inline Vec sample_hemisphere_uniform(const Vec& normal) {
  Vec vec = sample_sphere_uniform();
  // if the normal and vec are NOT in the same hemisphere, invert vec
  return (glm::dot(vec, normal) > 0.0) ? vec : -vec;
}

// Returns a cosine sampled vector in the hemisphere of the z-axis.
// https://raytracing.github.io/books/RayTracingTheRestOfYourLife.html#generatingrandomdirections/cosinesamplingahemisphere
inline Vec sample_hemisphere_cosine() {
  double r   = random::rand();          // r   = random in [0, 1)
  double phi = random::rand(0, 2*M_PI); // phi = random in [0, 2pi)
  auto x = cos(phi)*sqrt(r);             // x = sqrt(r) * cos(phi)
  auto y = sin(phi)*sqrt(r);             // y = sqrt(r) * sin(phi)
  auto z = sqrt(1-r);                    // z = sqrt(1 - r)
  return Vec(x, y, z);
}

// Returns a cosine sampled vector in the hemisphere of the normal.
// This is cosine-weighted in the hemisphere of the normal vector.
inline Vec sample_hemisphere_cosine(const Vec& normal) {
  Vec vec = sample_hemisphere_cosine();
  return glm::normalize(vec::change_basis(normal, vec)); // TODO: need to normalize ?
}


} // namespace raytracer::random
