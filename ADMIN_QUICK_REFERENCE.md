# FloraScan Admin Quick Reference Guide

## 🎯 Admin Features Quick Start

### Accessing Admin Features

**Requirements:**

- Admin role assigned in Supabase user metadata
- Must be logged into the app

**What You See:**

- Two additional tabs in the bottom navigation: "Crops" and "Activity"
- Regular users do NOT see these tabs

---

## 🌱 Managing Crops

### Add a New Crop

**Steps:**

1. Tap "Crops" tab (bottom navigation)
2. Tap **+ button** (floating action button, bottom right)
3. Fill in all fields:
   - **Crop Name**: e.g., "Tomato", "Lettuce"
   - **SPAD Index**: Reference chlorophyll value
   - **Leaf Length**: Standard length in cm
   - **Leaf Width**: Standard width in cm
   - **Perimeter**: Standard leaf perimeter in cm
   - **Aspect Ratio**: Length ÷ Width
   - **Color**: Select from dropdown
4. Tap "Save Crop"
5. ✅ Crop created! Regular users can now select it

**⏱️ Time to Complete:** ~2-3 minutes

---

### Edit an Existing Crop

**Steps:**

1. Tap "Crops" tab
2. Find the crop in the list
3. Tap the **⋮ menu** (three dots)
4. Select "Edit"
5. Modify any field
6. Tap "Update Crop"
7. ✅ Changes saved! History recorded automatically

**What Gets Tracked:**

- Which fields changed
- Old values → New values
- Admin name and timestamp
- Visible in Activity tab

---

### Delete a Crop

**Steps:**

1. Tap "Crops" tab
2. Find the crop
3. Tap **⋮ menu** → "Delete"
4. Confirm deletion in popup
5. ✅ Deleted (but logged for recovery)

**⚠️ Warning:**

- Deletion is recorded but cannot be undone
- Previous data is preserved in history
- Regular users can no longer select this crop

---

### View Crop History

**Steps:**

1. Tap "Crops" tab
2. Find the crop
3. Tap **⋮ menu** → "View History"
4. See all events:
   - 📝 Created: When and by whom
   - ✏️ Updated: What changed, before/after values
   - 🗑️ Deleted: When and by whom

---

## 📊 Activity Log

### View All Admin Actions

**Steps:**

1. Tap "Activity" tab (bottom navigation)
2. See all actions in reverse chronological order
3. Tap any row to expand and see details

**Information Visible:**

- Action Type (Created/Updated/Deleted)
- Crop Name
- Admin Name who performed action
- Date & Time
- Complete change details

### Filter Activity Logs

**By Action Type:**

1. Use dropdown at top of Activity tab
2. Choose: All, Created Crop, Updated Crop, or Deleted Crop
3. List automatically filters

**Clear Filters:**

- Tap ❌ button to reset all filters

---

## 🔍 Understanding Crop Validation

### How It Works for Users

When a user scans a leaf:

1. System analyzes the leaf
2. Compares measurements against selected crop
3. Generates match percentage
4. Takes action based on confidence:

| Confidence | Match % | What Happens                          |
| ---------- | ------- | ------------------------------------- |
| **High**   | ≥80%    | ✅ Leaf saved immediately             |
| **Medium** | 50-80%  | ⚠️ Warning dialog shown               |
| **Low**    | <50%    | 🚫 Blocked - must select correct crop |

### What Users See

**High Confidence (No Dialog):**

- Green checkmark
- "Leaf scanned successfully"
- Automatic save

**Medium Confidence (Warning Dialog):**

- Yellow warning icon
- "I am not fully confident..."
- Shows top 3 crop suggestions
- User can confirm or cancel

**Low Confidence (Blocking):**

- Red warning icon
- "This leaf is NOT a match"
- Shows top 3 correct suggestions
- User must select correct crop and rescan

---

## 📈 Best Practices for Admins

### Entering Accurate Crop Data

**Tip 1: Standard Measurements**

- Use averages from multiple healthy plants
- Measure at mid-season when plant is mature
- Use consistent units (always cm)

**Tip 2: SPAD Values**

- Measure with chlorophyll meter on multiple leaves
- Record under similar lighting conditions
- Use the average value

**Tip 3: Color Selection**

- Choose closest match from dropdown
- Can be updated later if needed
- Affects validation accuracy

**Tip 4: Aspect Ratio**

- Calculated as Length ÷ Width
- Example: 15cm ÷ 15cm = 1.0 (square)
- Example: 22cm ÷ 10cm = 2.2 (elongated)

### Monitoring System Health

**Regular Checks:**

- Review Activity tab weekly for any issues
- Check if validation is rejecting too many scans
- Verify crop profiles match reality

**If Validation is Too Strict:**

- Edit the crop profile
- Slightly increase measurements (±2-3%)
- Adjust tolerance thresholds (in code)

**If Validation is Too Loose:**

- Edit to make measurements more precise
- Update if agricultural standards changed
- Consider creating sub-varieties

### Managing Multiple Crops

**Organization Tips:**

- Name crops clearly and consistently
- Include variety if relevant (e.g., "Tomato - Cherry")
- Keep similar crops similar (don't vary too much)
- Document why each crop was added

**Handling Duplicates:**

- Delete old duplicate crops
- Keep the most accurate version
- Activity log shows which was used

---

## ⚙️ Validation Thresholds

### Current Tolerance Settings

These control how similar a scanned leaf must be to match a crop:

| Parameter    | Tolerance | Example                       |
| ------------ | --------- | ----------------------------- |
| Length       | ±15%      | 15cm ± 2.25cm = 12.75-17.25cm |
| Width        | ±15%      | 15cm ± 2.25cm = 12.75-17.25cm |
| Perimeter    | ±15%      | 48cm ± 7.2cm = 40.8-55.2cm    |
| Aspect Ratio | ±20%      | 1.0 ± 0.2 = 0.8-1.2           |
| Color Hue    | ±30°      | 100° ± 30° = 70-130°          |
| SPAD         | ±10       | 45 ± 10 = 35-55               |

### To Adjust Thresholds

**If too many false rejections:**

1. Open `lib/src/crop_service.dart`
2. Find constants near top of class
3. Increase tolerance percentages (e.g., 15% → 18%)
4. Rebuild app

**If too many false acceptances:**

1. Decrease tolerance percentages
2. This makes validation stricter
3. Test before releasing

---

## 📋 Common Admin Tasks

### Task: Add Cucumber Crop

```
1. Tap Crops → + button
2. Name: Cucumber
3. SPAD: 42.1
4. Length: 15.2 cm
5. Width: 15.2 cm
6. Perimeter: 48.3 cm
7. Ratio: 0.98
8. Color: Dark Green
9. Save
```

### Task: Add Coffee Crop

```
1. Tap Crops → + button
2. Name: Robusta Coffee
3. SPAD: 52.4
4. Length: 22.5 cm
5. Width: 10.2 cm
6. Perimeter: 53.8 cm
7. Ratio: 2.21
8. Color: Deep Glossy Green
9. Save
```

### Task: Update Crop After Field Study

```
1. Tap Crops → find crop
2. Menu → Edit
3. Adjust measurements based on new data
4. Update
5. Check Activity log to confirm change logged
6. Check Crop History to see before/after
```

### Task: Review Yesterday's Admin Activity

```
1. Tap Activity
2. Look for entries from yesterday
3. Expand each to see details
4. Verify all actions are legitimate
```

### Task: Export Crop List

```
1. Open Supabase Dashboard
2. SQL Editor
3. Run: SELECT crop_name, created_by, created_date FROM florascan.crop_profiles
4. Export or take screenshot
```

---

## 🆘 Troubleshooting

### Problem: Can't see Crops/Activity tabs

**Solution:**

1. Log out completely
2. Log back in
3. If still not visible, check Supabase:
   - User metadata must have `"role": "admin"`
   - Contact your administrator

### Problem: Created a crop but users can't see it

**Solution:**

1. Verify crop was saved (check in Crops list)
2. Tell users to:
   - Close the app completely
   - Open again
   - Tap Scan → Should see new crop

### Problem: Validation is blocking good leaves

**Solution:**

1. Edit the crop profile
2. Verify measurements are accurate
3. Consider if crop measurements are too strict
4. Increase perimeter/width slightly
5. Re-test scanning

### Problem: Two different people made same crop

**Solution:**

1. Check Activity tab to see who created each
2. Compare the measurements in Crop History
3. Keep the more accurate one
4. Delete the duplicate

---

## 📞 Quick Help

| Need                      | Solution                                   |
| ------------------------- | ------------------------------------------ |
| **Can't log in**          | Verify Supabase credentials with developer |
| **Forgot admin password** | Use Supabase reset link                    |
| **Need to reset data**    | Contact developer - database backup needed |
| **Validation too strict** | Edit crop & increase measurements          |
| **Validation too loose**  | Edit crop & make measurements more precise |
| **Activity log errors**   | Check browser console for error messages   |
| **Database down**         | Check Supabase status: status.supabase.com |

---

## 📱 Mobile Tips

### For Smaller Screens

- Tap and hold on crop card to see full details
- Use landscape mode for Activity tab
- Swipe left/right to navigate tabs

### Performance

- Activity logs load faster with filters applied
- Crops list loads in ~2 seconds
- All changes sync immediately to database

---

## 📞 Support Contact

For issues, contact:

- **Technical Support**: [Your Support Email]
- **Database Issues**: [Your DBA Email]
- **Feature Requests**: [Your PM Email]

---

**Last Updated**: May 31, 2026
**For Version**: 1.0.0
**Questions?** Check IMPLEMENTATION_GUIDE.md for detailed information
