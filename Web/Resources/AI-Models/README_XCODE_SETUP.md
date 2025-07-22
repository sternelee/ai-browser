# Xcode Setup Required

After running the bundle script, you need to:

1. **Add the AI-Models folder to Xcode:**
   - Right-click on Web/Resources in Xcode
   - Choose "Add Files to Web..."  
   - Select the AI-Models folder
   - ✅ Check "Copy items if needed"
   - ✅ Check "Create folder references" (not groups)
   - ✅ Add to target: Web

2. **Verify bundle resources:**
   - Build Settings → Build Phases → Copy Bundle Resources  
   - Ensure AI-Models folder is listed
   - If not, drag it there manually

3. **Test the integration:**
   - Build and run the app
   - Check that BundledModelService finds the model
   - AI should work out-of-the-box!

Model file: gemma-3n-E2B-it-Q8_0.gguf
Size: 4.5G
