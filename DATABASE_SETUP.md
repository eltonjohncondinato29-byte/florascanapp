# Supabase Database Setup Guide - FloraScan Crop Management System

This guide provides the SQL migrations needed to set up the Admin Crop Management, Crop Validation, and Activity Log systems in Supabase.

## Prerequisites

- Access to Supabase dashboard
- "florascan" schema already created
- Admin privileges in the Supabase project

## Database Tables

### 1. Crop Profiles Table

```sql
-- Create crop_profiles table for storing standard crop measurements
CREATE TABLE IF NOT EXISTS florascan.crop_profiles (
  id VARCHAR(255) PRIMARY KEY,
  crop_name VARCHAR(255) NOT NULL UNIQUE,
  reference_spad_index DOUBLE PRECISION NOT NULL,
  standard_leaf_length_cm DOUBLE PRECISION NOT NULL,
  standard_leaf_width_cm DOUBLE PRECISION NOT NULL,
  standard_leaf_color VARCHAR(255) NOT NULL,
  standard_leaf_perimeter_cm DOUBLE PRECISION NOT NULL,
  standard_aspect_ratio DOUBLE PRECISION NOT NULL,
  created_by VARCHAR(255) NOT NULL,
  created_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_by VARCHAR(255),
  last_modified_date TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on crop_name for faster lookups
CREATE INDEX IF NOT EXISTS idx_crop_profiles_name ON florascan.crop_profiles (crop_name);
CREATE INDEX IF NOT EXISTS idx_crop_profiles_created_date ON florascan.crop_profiles (created_date DESC);
```

### 2. Admin Activity Logs Table

```sql
-- Create admin_activity_logs table for audit trail
CREATE TABLE IF NOT EXISTS florascan.admin_activity_logs (
  id VARCHAR(255) PRIMARY KEY,
  admin_id VARCHAR(255) NOT NULL,
  admin_name VARCHAR(255) NOT NULL,
  action_type VARCHAR(50) NOT NULL,
  crop_name VARCHAR(255) NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  change_description TEXT,
  previous_values JSONB,
  new_values JSONB,
  device_ip_address VARCHAR(255),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for activity log queries
CREATE INDEX IF NOT EXISTS idx_activity_logs_admin ON florascan.admin_activity_logs (admin_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_crop ON florascan.admin_activity_logs (crop_name);
CREATE INDEX IF NOT EXISTS idx_activity_logs_action ON florascan.admin_activity_logs (action_type);
CREATE INDEX IF NOT EXISTS idx_activity_logs_timestamp ON florascan.admin_activity_logs (timestamp DESC);
```

### 3. Crop History Table

```sql
-- Create crop_history table for tracking all changes to crops
CREATE TABLE IF NOT EXISTS florascan.crop_history (
  id VARCHAR(255) PRIMARY KEY,
  crop_id VARCHAR(255) NOT NULL REFERENCES florascan.crop_profiles(id) ON DELETE CASCADE,
  crop_name VARCHAR(255) NOT NULL,
  event_type VARCHAR(50) NOT NULL,
  admin_id VARCHAR(255) NOT NULL,
  admin_name VARCHAR(255) NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  previous_values JSONB,
  new_values JSONB,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for crop history queries
CREATE INDEX IF NOT EXISTS idx_crop_history_crop ON florascan.crop_history (crop_id);
CREATE INDEX IF NOT EXISTS idx_crop_history_admin ON florascan.crop_history (admin_id);
CREATE INDEX IF NOT EXISTS idx_crop_history_timestamp ON florascan.crop_history (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_crop_history_event ON florascan.crop_history (event_type);
```

## User Role Setup

### Add Admin Role to Supabase Auth

To enable admin-only features, add the "role" field to user metadata:

1. Go to Supabase Dashboard → Authentication → Users
2. Select a user to make an admin
3. Click "Edit user" or access the user data
4. In the "user_metadata" field, add:

```json
{
  "username": "John Cruz",
  "role": "admin"
}
```

Alternatively, use SQL in Supabase SQL editor:

```sql
-- Update user metadata to add admin role
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || '{"role": "admin"}'
WHERE email = 'admin@example.com';
```

### Regular User Metadata

Regular users should have metadata like:

```json
{
  "username": "Researcher Name",
  "role": "regular"
}
```

## Seeding Initial Crops

Run these SQL commands to seed the initial crops with example data:

```sql
-- Insert Cucumber crop profile
INSERT INTO florascan.crop_profiles (
  id,
  crop_name,
  reference_spad_index,
  standard_leaf_length_cm,
  standard_leaf_width_cm,
  standard_leaf_color,
  standard_leaf_perimeter_cm,
  standard_aspect_ratio,
  created_by,
  created_date
) VALUES (
  '1000_cucumber',
  'Cucumber',
  42.1,
  15.2,
  15.2,
  'Dark Green',
  48.3,
  0.98,
  'System Admin',
  CURRENT_TIMESTAMP
);

-- Insert Robusta Coffee crop profile
INSERT INTO florascan.crop_profiles (
  id,
  crop_name,
  reference_spad_index,
  standard_leaf_length_cm,
  standard_leaf_width_cm,
  standard_leaf_color,
  standard_leaf_perimeter_cm,
  standard_aspect_ratio,
  created_by,
  created_date
) VALUES (
  '1001_robusta_coffee',
  'Robusta Coffee',
  52.4,
  22.5,
  10.2,
  'Deep Glossy Green',
  53.8,
  2.21,
  'System Admin',
  CURRENT_TIMESTAMP
);

-- Record the creation in crop history
INSERT INTO florascan.crop_history (
  id,
  crop_id,
  crop_name,
  event_type,
  admin_id,
  admin_name,
  timestamp,
  description
) VALUES
  ('h_1000', '1000_cucumber', 'Cucumber', 'created', 'system', 'System', CURRENT_TIMESTAMP, 'Initial crop profile created'),
  ('h_1001', '1001_robusta_coffee', 'Robusta Coffee', 'created', 'system', 'System', CURRENT_TIMESTAMP, 'Initial crop profile created');
```

## Row Level Security (RLS) Policies

### Crop Profiles - Read Access for All, Write for Admins

```sql
-- Enable RLS on crop_profiles
ALTER TABLE florascan.crop_profiles ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read crops
CREATE POLICY "Allow all users to read crops"
ON florascan.crop_profiles FOR SELECT
USING (TRUE);

-- Only admins can insert crops
CREATE POLICY "Allow admins to create crops"
ON florascan.crop_profiles FOR INSERT
WITH CHECK (auth.jwt() ->> 'user_metadata'->>'role' = 'admin');

-- Only admins can update crops
CREATE POLICY "Allow admins to update crops"
ON florascan.crop_profiles FOR UPDATE
USING (auth.jwt() ->> 'user_metadata'->>'role' = 'admin')
WITH CHECK (auth.jwt() ->> 'user_metadata'->>'role' = 'admin');

-- Only admins can delete crops
CREATE POLICY "Allow admins to delete crops"
ON florascan.crop_profiles FOR DELETE
USING (auth.jwt() ->> 'user_metadata'->>'role' = 'admin');
```

### Activity Logs - Read for Admins, Write for System

```sql
-- Enable RLS on admin_activity_logs
ALTER TABLE florascan.admin_activity_logs ENABLE ROW LEVEL SECURITY;

-- Only admins can read activity logs
CREATE POLICY "Allow admins to read activity logs"
ON florascan.admin_activity_logs FOR SELECT
USING (auth.jwt() ->> 'user_metadata'->>'role' = 'admin');

-- System and admins can insert activity logs
CREATE POLICY "Allow logging of admin activities"
ON florascan.admin_activity_logs FOR INSERT
WITH CHECK (TRUE); -- Allow app to insert logs
```

### Crop History - Read for Admins, Write for System

```sql
-- Enable RLS on crop_history
ALTER TABLE florascan.crop_history ENABLE ROW LEVEL SECURITY;

-- Only admins can read crop history
CREATE POLICY "Allow admins to read crop history"
ON florascan.crop_history FOR SELECT
USING (auth.jwt() ->> 'user_metadata'->>'role' = 'admin');

-- System can insert history records
CREATE POLICY "Allow logging of crop history"
ON florascan.crop_history FOR INSERT
WITH CHECK (TRUE); -- Allow app to insert history
```

## Verification Queries

After setting up the database, verify everything is working:

```sql
-- Count crops available
SELECT COUNT(*) as crop_count FROM florascan.crop_profiles;

-- View all crops
SELECT crop_name, created_by, created_date FROM florascan.crop_profiles ORDER BY created_date DESC;

-- View activity logs
SELECT admin_name, action_type, crop_name, timestamp FROM florascan.admin_activity_logs ORDER BY timestamp DESC LIMIT 10;

-- View crop history
SELECT crop_name, event_type, admin_name, timestamp FROM florascan.crop_history ORDER BY timestamp DESC LIMIT 10;
```

## Troubleshooting

### Issue: "Permission denied" when accessing crop data

**Solution**: Check that RLS policies are correctly set up and user has appropriate role in metadata.

### Issue: Admin cannot create/edit crops

**Solution**:

1. Verify user has "role": "admin" in user_metadata
2. Check RLS policies for crop_profiles table
3. Ensure the app is using authenticated Supabase client

### Issue: Activity logs not appearing

**Solution**: Check that the app is successfully calling `CropService.logActivity()` after admin actions.

## Maintenance

### Backup Crops Regularly

```sql
-- Export all crop data
SELECT * FROM florascan.crop_profiles;
```

### Archive Old Activity Logs (Optional)

```sql
-- Keep only last 90 days of logs
DELETE FROM florascan.admin_activity_logs
WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

### Monitor Database Usage

```sql
-- Check table sizes
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'florascan'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## Support

For issues or questions about the crop management system:

1. Check the Activity Log page in the app for detailed operation history
2. Review crop history for each crop to see all modifications
3. Contact your system administrator if you need to reset or recover data
