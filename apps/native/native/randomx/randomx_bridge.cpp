#include <randomx.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

#if defined(_WIN32)
#define MM_EXPORT __declspec(dllexport)
#else
#define MM_EXPORT __attribute__((visibility("default")))
#endif

namespace {
std::mutex engine_mutex;
randomx_cache* cache_handle = nullptr;
randomx_dataset* dataset_handle = nullptr;
randomx_vm* vm_handle = nullptr;
int active_mode = -1;

bool decode_hex_32(const char* input, std::uint8_t output[32]) {
  if (input == nullptr || std::strlen(input) != 64) return false;
  for (int i = 0; i < 32; ++i) {
    unsigned int value = 0;
    if (std::sscanf(input + (i * 2), "%2x", &value) != 1) return false;
    output[i] = static_cast<std::uint8_t>(value);
  }
  return true;
}

void release_locked() {
  if (vm_handle) randomx_destroy_vm(vm_handle);
  if (dataset_handle) randomx_release_dataset(dataset_handle);
  if (cache_handle) randomx_release_cache(cache_handle);
  vm_handle = nullptr;
  dataset_handle = nullptr;
  cache_handle = nullptr;
  active_mode = -1;
}
}

extern "C" MM_EXPORT int mm_randomx_init(const char* seed_hash_hex, int request_fast_mode) {
  std::lock_guard<std::mutex> lock(engine_mutex);
  std::uint8_t seed[32];
  if (!decode_hex_32(seed_hash_hex, seed)) return -1;
  release_locked();

  const randomx_flags supported = randomx_get_flags();
  const randomx_flags cache_flags = static_cast<randomx_flags>(
    static_cast<int>(supported) & (RANDOMX_FLAG_JIT | RANDOMX_FLAG_ARGON2)
  );
  cache_handle = randomx_alloc_cache(cache_flags);
  if (!cache_handle) return -2;
  randomx_init_cache(cache_handle, seed, sizeof(seed));

  randomx_flags vm_flags = static_cast<randomx_flags>(
    static_cast<int>(supported) & (RANDOMX_FLAG_HARD_AES | RANDOMX_FLAG_JIT)
  );

  if (request_fast_mode != 0) {
    dataset_handle = randomx_alloc_dataset(RANDOMX_FLAG_DEFAULT);
    if (dataset_handle) {
      const unsigned long total = randomx_dataset_item_count();
      const unsigned int hw = std::max(1u, std::thread::hardware_concurrency());
      const unsigned int workers = std::min<unsigned long>(hw, total);
      std::vector<std::thread> threads;
      threads.reserve(workers);
      for (unsigned int i = 0; i < workers; ++i) {
        const unsigned long begin = (total * i) / workers;
        const unsigned long end = (total * (i + 1)) / workers;
        threads.emplace_back([=]() {
          randomx_init_dataset(dataset_handle, cache_handle, begin, end - begin);
        });
      }
      for (auto& thread : threads) thread.join();
      vm_flags = static_cast<randomx_flags>(static_cast<int>(vm_flags) | RANDOMX_FLAG_FULL_MEM);
    }
  }

  vm_handle = randomx_create_vm(vm_flags, cache_handle, dataset_handle);
  if (!vm_handle) {
    release_locked();
    return -3;
  }
  active_mode = dataset_handle ? 1 : 0;
  return active_mode;
}

extern "C" MM_EXPORT int mm_randomx_hash(
  const std::uint8_t* input,
  std::size_t input_size,
  std::uint8_t* output
) {
  if (!input || input_size == 0 || !output) return -1;
  std::lock_guard<std::mutex> lock(engine_mutex);
  if (!vm_handle) return -2;
  randomx_calculate_hash(vm_handle, input, input_size, output);
  return 0;
}

extern "C" MM_EXPORT int mm_randomx_mode() {
  std::lock_guard<std::mutex> lock(engine_mutex);
  return active_mode;
}

extern "C" MM_EXPORT void mm_randomx_release() {
  std::lock_guard<std::mutex> lock(engine_mutex);
  release_locked();
}
