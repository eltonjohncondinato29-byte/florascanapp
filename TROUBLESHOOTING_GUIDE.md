# FloraScan Crop Management System - Troubleshooting Guide

## 🆘 Quick Troubleshooting Index

| Issue                   | Quick Fix              | Details                 | Contact |
| ----------------------- | ---------------------- | ----------------------- | ------- |
| Crops not appearing     | Restart app            | See Crop Loading Issues | Admin   |
| Can't create crops      | Check admin role       | See Admin Access Issues | Admin   |
| Validation too strict   | Edit crop measurements | See Validation Issues   | Admin   |
| Activity log empty      | Refresh page           | See Activity Log Issues | Admin   |
| Validation dialog wrong | Check crop data        | See Validation Issues   | Dev     |

---

## 🔴 Critical Issues

### 1. Database Connection Failed

**Symptoms:**

- App shows "Connection error" on startup
- Can't create, edit, or delete crops
- Activity log won't load

**Diagnosis:**

```
Check Supabase Status:
1. Visit status.supabase.com
2. Look for incidents in your region
3. Check credentials in main.dart
```

**Fix:**

```
Step 1: Verify Supabase URL
  - Open main.dart
  - Find: supabase.initialize(url: '...')
  - Ensure URL matches Supabase dashboard

Step 2: Verify API Key
  - Check api_key matches Supabase anon key
  - Don't use service role key

Step 3: Restart Supabase
  - Go to Supabase Dashboard
  - Check if project is active
  - Restart if needed
```

**Prevention:**

- Monitor database uptime
- Keep credentials secure
- Test connection daily

---

### 2. Admin Features Not Visible

**Symptoms:**

- No "Crops" or "Activity" tabs visible
- User thinks they're admin but can't access features

**Diagnosis:**

```dart
// Check if user is actually admin
1. Go to Supabase Dashboard
2. Click Authentication → Users
3. Find the user
4. Check user_metadata
5. Should show: "role": "admin"
```

**Fix:**

```
Option 1: Set user as admin in Supabase
  1. Auth → Users → Select user
  2. Click "Copy" next to user_metadata
  3. Paste into editor
  4. Add: "role": "admin"
  5. Click "Update user metadata"

Option 2: User needs to re-login
  1. Sign out completely
  2. Sign back in
  3. Metadata will reload

Option 3: Force app reload
  1. Close app completely (swipe away)
  2. Reopen app
  3. Sign back in
```

**Verification:**

```
After fix, admin should see in app:
- Extra navigation tabs
- Floating action button on Crops tab
- Activity tab with logs
```

---

### 3. Crops Table Missing from Database

**Symptoms:**

- Error: "relation crop_profiles does not exist"
- Can't select crops when scanning

**Fix:**

```
1. Open Supabase SQL Editor
2. Run setup from DATABASE_SETUP.md:
   - Copy all SQL for table creation
   - Execute in SQL editor
   - Run verification queries

3. If still failing:
   - Check schema: SELECT * FROM information_schema.tables
   - Verify florascan schema exists
   - Verify crop_profiles table exists
   - Check permissions on schema
```

---

## 🟠 High Priority Issues

### 1. Validation Blocking All Scans

**Symptoms:**

- Every scan shows "This leaf is NOT a match"
- Red blocking dialog every time
- Can't save any scans

**Root Causes:**

- Crop measurements too narrow
- Scanned measurements calculated incorrectly
- Tolerance thresholds too strict

**Fix:**

```
Step 1: Verify crop measurements are realistic
  1. Go to Crops tab (admin)
  2. Check each crop's measurements
  3. Compare with actual plants
  4. If wrong, click menu → Edit
  5. Adjust to realistic values

Step 2: Test with a known good crop
  1. Create a very flexible crop (wide tolerances)
  2. Example: Leaf Length 10-20cm (realistic range)
  3. Try scanning with this crop
  4. If it works, previous crops had wrong data

Step 3: Increase tolerances (temporary test)
  1. Edit crop
  2. Change measurements to match scanned values exactly
  3. Try scanning again
  4. If it saves, problem is tolerance settings
```

**Prevention:**

- Use realistic crop measurements
- Test new crops before users scan with them
- Monitor first few scans with new crops

---

### 2. Activity Log Shows Wrong Actions

**Symptoms:**

- Activity log shows deletions that didn't happen
- Shows updates with no changes
- Admin name is wrong
- Timestamps are incorrect

**Diagnosis:**

```
1. Check database directly:
   - Open Supabase → SQL Editor
   - SELECT * FROM florascan.admin_activity_logs ORDER BY timestamp DESC

2. Look for:
   - Duplicate entries
   - Wrong admin ID
   - Incorrect change_details
   - Timestamp issues
```

**Fix:**

```
If log entries are wrong:
  1. Contact database admin
  2. May need to clean up logs manually
  3. SQL: DELETE FROM florascan.admin_activity_logs WHERE id = '...'

If timestamps wrong:
  1. Check server time vs local time
  2. Ensure app device time is correct
  3. Check Supabase region settings
```

---

### 3. Crop Validation Dialog Shows Wrong Crops

**Symptoms:**

- Top 3 suggestions are inaccurate
- Shows crops with 0% match
- Match percentages add up to more than 100%

**Root Cause:**

- Validation algorithm error
- Database returning wrong crops
- Measurement data corrupted

**Fix:**

```
Step 1: Verify crop data in database
  SELECT * FROM florascan.crop_profiles

Step 2: Check calculation manually
  - Scanned: Length 15cm, Width 14cm
  - Crop: Length 15cm, Width 15cm
  - Expected match: ~97% (very similar)
  - If actual shows 50%, algorithm issue

Step 3: Review CropService code
  - Open lib/src/crop_service.dart
  - Verify _calculateMatchPercentage() logic
  - Check weighting values sum to 100%
  - Test with debugPrint statements

Step 4: Check for null/invalid measurements
  - Some crops might have null values
  - Could cause calculation errors
```

---

## 🟡 Medium Priority Issues

### 1. Slow Crop Loading

**Symptoms:**

- Takes 5+ seconds to load crop list
- Activity log takes forever to appear
- App feels unresponsive

**Possible Causes:**

- Large number of crops (1000+)
- Poor internet connection
- Supabase performance issue
- Unindexed queries

**Fix:**

```
Quick test:
  1. Open browser DevTools (F12)
  2. Network tab
  3. Look for slow requests to Supabase
  4. Check response time

If slow (>2 sec):
  - Check internet connection
  - Try from different network
  - Check Supabase metrics
  - See if other operations are slow

If very slow (>5 sec):
  - Verify indexes exist:
    SELECT * FROM pg_indexes WHERE tablename = 'crop_profiles'

  - Rebuild indexes if missing:
    REINDEX TABLE florascan.crop_profiles
```

---

### 2. Activity Log Pagination Issues

**Symptoms:**

- Can't see older activity logs
- No scroll/pagination controls
- Too many entries to display

**Fix:**

```
Current implementation limitation:
  - Loads all logs at once
  - Could be slow with thousands of entries

Workaround:
  1. Filter by recent date (last 30 days)
  2. Archive old logs to separate table
  3. Delete logs older than 1 year

For production:
  - Add pagination to AdminActivityLogPage
  - Limit to 50 entries per page
  - Add date range filter
```

---

### 3. Duplicate Crop Names

**Symptoms:**

- Same crop appears twice in list
- Confusing for users
- Activity log shows duplicates

**Fix:**

```
Step 1: Find duplicates
  SELECT crop_name, COUNT(*) FROM florascan.crop_profiles
  GROUP BY crop_name HAVING COUNT(*) > 1

Step 2: Compare the duplicates
  SELECT * FROM florascan.crop_profiles
  WHERE crop_name = 'Cucumber'
  ORDER BY created_date

Step 3: Keep the best one, delete the other
  1. Check which has more accurate measurements
  2. Check which has correct admin info
  3. Delete the inferior copy:
     DELETE FROM florascan.crop_profiles WHERE id = '...'
  4. Verify only one remains
```

**Prevention:**

- Check for existing crop before creating
- Use unique constraint on crop name
- Review weekly for duplicates

---

## 🟢 Low Priority Issues

### 1. UI Display Issues

**Symptoms:**

- Text cutoff on mobile
- Button text not centered
- Colors look wrong

**Fix:**

```
Mobile layout issues:
  1. Check device screen size
  2. Try landscape/portrait orientation
  3. Zoom out if text too large

Color issues:
  - May be device settings
  - Check theme in app settings
  - Compare with screenshot

Button issues:
  - Force app reload
  - Clear app cache
```

---

### 2. Slow Image Analysis

**Symptoms:**

- Takes 10+ seconds to analyze leaf
- App becomes unresponsive during scanning
- Battery drains quickly

**Fix:**

```
This is normal for image processing:
  - Leaf analysis uses ML model
  - Can take 5-15 seconds depending on image quality
  - Happens on device, not server

To improve:
  1. Ensure good lighting when scanning
  2. Keep leaf flat and centered
  3. Don't move during capture
  4. Close other apps to free RAM
  5. Update to latest Flutter version
```

---

### 3. User Preferences Not Saved

**Symptoms:**

- App forgets selected crop on restart
- Settings reset after close
- Last scan history missing

**Expected Behavior:**

- Current implementation doesn't persist preferences
- Crop selected in current session only
- After close/reopen, must select again

**If persistence needed:**

```
Add to lib/src/home_page.dart:

final prefs = await SharedPreferences.getInstance();

// Save selected crop
prefs.setString('lastSelectedCrop', _selectedCropProfile?.id ?? '');

// Load on startup
final savedCropId = prefs.getString('lastSelectedCrop');
```

---

## 📋 Systematic Troubleshooting Process

### 1. Isolate the Problem

**Ask:**

- When did this start?
- What were you doing?
- Does it happen for all users or just one?
- Does it happen on all devices or one?
- Can you reproduce it?

**This helps identify:**

- User-specific vs system-wide issues
- Recent changes that caused it
- Device-specific limitations

### 2. Gather Information

**Collect:**

```
From User:
- Screenshot of error
- Device model and OS version
- Internet connection type
- When last successful use was

From System:
- Browser console errors (F12)
- Network requests in dev tools
- Supabase logs
- Database query results
- Recent code changes
```

### 3. Review Logs

**Check These in Order:**

```
1. Browser Console (F12 → Console)
   - JavaScript errors
   - Network errors
   - Permission errors

2. Supabase Logs
   - Go to Supabase Dashboard
   - Check API logs
   - Look for 401/403 errors

3. Database Logs
   - Check RLS policy denials
   - Look for slow queries
   - Verify indexes used
```

### 4. Test Isolation

**Test each layer:**

```
1. Database - Can you query directly?
   SELECT COUNT(*) FROM florascan.crop_profiles

2. API - Can you call Supabase endpoints?
   Use curl or Postman

3. App - Is app receiving data?
   Add debugPrint() statements

4. UI - Is data displaying?
   Check widget build tree
```

### 5. Solution Implementation

**Try fixes in this order:**

1. Simplest fix first (restart, clear cache)
2. Configuration changes (settings, metadata)
3. Database changes (data, indexes)
4. Code changes (if required)
5. Escalate if needed

---

## 🔧 Common Fixes Summary

| Issue                 | Quick Fix             | Time  | Success Rate |
| --------------------- | --------------------- | ----- | ------------ |
| Not seeing admin tabs | Re-login              | 1 min | 95%          |
| Crops won't load      | Restart app           | 2 min | 80%          |
| Validation too strict | Edit crop             | 5 min | 90%          |
| Activity log blank    | Refresh page          | 1 min | 85%          |
| Database error        | Check Supabase status | 2 min | 70%          |
| Slow performance      | Clear cache           | 3 min | 60%          |

---

## 📞 When to Escalate

### Contact Support When:

**For Admin Issues:**

- Can't create/edit/delete crops
- Activity log not recording
- Need to reset user permissions
- Database seems corrupted

**For User Issues:**

- Users can't scan leaves
- Validation always wrong
- Crop not appearing in list
- Scans not saving

**For Technical Issues:**

- Database connection errors
- Performance degradation
- Data inconsistencies
- Security concerns

---

## 📊 Health Checks

**Run Daily:**

```
1. Verify Supabase is up
   - Visit Supabase dashboard
   - Check green indicators

2. Spot check database
   - SELECT COUNT(*) FROM florascan.crop_profiles
   - SELECT COUNT(*) FROM florascan.admin_activity_logs
   - Verify counts are reasonable

3. Test as admin user
   - Can login?
   - Can see admin tabs?
   - Can view activity log?
```

**Run Weekly:**

```
1. Review activity logs for anomalies
   - Any suspicious deletions?
   - Unusual number of updates?
   - Unknown admins making changes?

2. Verify crop data accuracy
   - Sample check 5 crops
   - Verify measurements look realistic
   - Check for duplicates

3. Test end-to-end workflow
   - Select crop → Scan → Save
   - Verify data reaches database
```

**Run Monthly:**

```
1. Audit admin access
   - Who has admin role?
   - Any inactive admins?
   - Remove former employees

2. Review validation thresholds
   - Rejection rate too high?
   - False acceptances?
   - Should tolerances change?

3. Database maintenance
   - Check query performance
   - Archive old logs (if implemented)
   - Verify backups working
```

---

## 📚 Documentation References

| Issue Type       | Document                       | Section              |
| ---------------- | ------------------------------ | -------------------- |
| Setup problems   | DATABASE_SETUP.md              | All sections         |
| Admin features   | ADMIN_QUICK_REFERENCE.md       | Managing Crops       |
| Validation logic | DEVELOPER_INTEGRATION_GUIDE.md | Validation Algorithm |
| Code changes     | DEVELOPER_INTEGRATION_GUIDE.md | Integration Points   |
| General help     | IMPLEMENTATION_GUIDE.md        | Troubleshooting      |

---

## 🚨 Emergency Procedures

### Data Loss Scenario

**If crops are accidentally deleted:**

```
1. Check Supabase backup
   - Most recent snapshot is restore point
   - Can restore from backup
   - Will lose changes after backup time

2. Export from crop_history table
   - Can reconstruct crop from history
   - May need manual cleanup
```

### Security Breach Scenario

**If unauthorized access suspected:**

```
1. Disable compromised user
   - Go to Supabase Auth
   - Disable user account

2. Review activity logs
   - Check what was accessed
   - Check what was changed

3. Restore clean backup
   - Restore crops from backup
   - May lose recent valid changes
```

### Performance Crisis Scenario

**If system becomes very slow:**

```
1. Check Supabase metrics
   - CPU, RAM, connections
   - Kill long-running queries if needed

2. Disable non-essential features
   - Disable real-time subscriptions
   - Disable logging temporarily

3. Scale up resources
   - Upgrade Supabase plan
   - Increase database resources

4. Optimize queries
   - Review slow query log
   - Add missing indexes
```

---

**Last Updated**: May 31, 2026
**Version**: 1.0.0
**For Questions**: See IMPLEMENTATION_GUIDE.md or contact support
