# MLX Swift Build Optimizations

## Critical Build Settings for AI Streaming Stability

Based on MLX Swift best practices and the current streaming issues, apply these Xcode build settings:

### Release Configuration (Required)
1. **Always use Release builds** when testing AI functionality
   - Debug builds are known to cause crashes with MLX Swift
   - Deep stack traces and memory issues are common in Debug mode

### Xcode Project Settings

#### Swift Compiler - Code Generation
- **Optimization Level**: `-O3` (Aggressive Optimizations)
  - Navigate to Build Settings → Swift Compiler - Code Generation
  - Set "Optimization Level" to "Optimize for Speed [-O3]"

#### Other Swift Flags  
- **Other Swift Flags**: Add `-O3` if not automatically included
  - Build Settings → Swift Compiler - Custom Flags → Other Swift Flags
  - Add: `-O3`

### Memory Management
- **Enable Automatic Reference Counting**: YES (should be default)
- **Metal Performance Shaders**: Enable for GPU acceleration

### Architecture Settings
- **Build Active Architecture Only**: NO (for Release)
- **Architectures**: `arm64` (Apple Silicon optimized)

## Manual Build Commands

If using command line builds, ensure Release configuration:

```bash
# Build in Release mode
xcodebuild -project Web.xcodeproj -scheme Web -configuration Release build

# Archive for distribution
xcodebuild -project Web.xcodeproj -scheme Web -configuration Release archive
```

## Verification

After applying these settings, verify in build logs:
- Swift compilation shows `-O3` flag
- No debug symbols in final binary
- Metal framework properly linked

## Expected Improvements

These optimizations should resolve:
- ✅ Streaming callback thread safety issues
- ✅ MLX Swift async generation crashes
- ✅ Memory pressure handling
- ✅ Token-by-token streaming stability

## Additional Recommendations

1. **Test on Device**: Always test AI functionality on actual hardware, not simulator
2. **Memory Monitoring**: Use Instruments to monitor memory usage during AI operations
3. **Thermal Monitoring**: Check thermal state integration is working correctly

## Known Issues Fixed

- **Thread 4: EXC_BAD_ACCESS** errors during async generation
- **Callback streaming failures** falling back to complete responses
- **Memory pressure crashes** during intensive AI operations

Apply these settings before testing the AI streaming fixes.