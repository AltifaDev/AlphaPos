import paramiko
import time
import jwt as pyjwt

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"
JWT_SECRET = "super-secret-jwt-token-with-at-least-32-characters-long"
MERCHANT_ID = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"

LOCAL_IMAGE = "/Users/mac/Library/Developer/CoreSimulator/Devices/3E4460FC-E15B-4B8C-885C-6B4D09E56DB0/data/Containers/Data/Application/BB74A846-4D14-4651-911B-F23BEE4E3442/Documents/floor_plan_1_1782111506.jpg"
FILENAME = "floor_plan_1_1782111506.jpg"
OBJECT_PATH = f"{MERCHANT_ID.lower()}/floor_plans/{FILENAME}"

def make_token(role="service_role"):
    payload = {"role": role, "iss": "supabase", "iat": int(time.time()), "exp": int(time.time()) + 3600}
    return pyjwt.encode(payload, JWT_SECRET, algorithm="HS256")

def run():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(hostname, username=username, password=password, timeout=30)

        # Step 1: Upload image to VPS via SFTP
        print(f"Step 1: Uploading {FILENAME} to VPS /tmp/...")
        sftp = ssh.open_sftp()
        sftp.put(LOCAL_IMAGE, f"/tmp/{FILENAME}")
        sftp.close()
        print("  ✅ Upload to VPS /tmp done")

        # Step 2: Upload to Supabase Storage via REST API (service_role token)
        service_token = make_token("service_role")
        print(f"\nStep 2: Uploading to Supabase Storage bucket 'product-media'...")
        print(f"  Object path: {OBJECT_PATH}")
        
        cmd_upload = (
            f"curl -s -X POST "
            f"'http://localhost:54321/storage/v1/object/product-media/{OBJECT_PATH}' "
            f"-H 'Authorization: Bearer {service_token}' "
            f"-H 'Content-Type: image/jpeg' "
            f"--data-binary @/tmp/{FILENAME} 2>&1"
        )
        stdin, stdout, stderr = ssh.exec_command(cmd_upload)
        resp = stdout.read().decode()
        print(f"  Storage upload response: {resp}")

        # Step 3: If upload failed (object exists), try PUT instead
        if "error" in resp.lower() and "duplicate" not in resp.lower():
            print("\nStep 2b: Trying PUT (update) instead...")
            cmd_put = (
                f"curl -s -X PUT "
                f"'http://localhost:54321/storage/v1/object/product-media/{OBJECT_PATH}' "
                f"-H 'Authorization: Bearer {service_token}' "
                f"-H 'Content-Type: image/jpeg' "
                f"--data-binary @/tmp/{FILENAME} 2>&1"
            )
            stdin, stdout, stderr = ssh.exec_command(cmd_put)
            print(f"  PUT response: {stdout.read().decode()}")

        # Step 4: Insert/upsert row into floor_plan_images on VPS
        print(f"\nStep 3: Upserting row in floor_plan_images on VPS...")
        FLOOR_PLAN_ID = "f4c86858-3b24-4354-a91e-d4506e29204f"  # Same UUID as local
        sql = f"""
INSERT INTO public.floor_plan_images (id, merchant_id, floor, image_filename, is_deleted, scale, offset_x, offset_y)
VALUES ('{FLOOR_PLAN_ID}', '{MERCHANT_ID}', 1, '{FILENAME}', false, 1.0, 0.0, 0.0)
ON CONFLICT (id) DO UPDATE SET
  image_filename = EXCLUDED.image_filename,
  is_deleted = false,
  scale = EXCLUDED.scale,
  offset_x = EXCLUDED.offset_x,
  offset_y = EXCLUDED.offset_y,
  updated_at = NOW();
"""
        sftp = ssh.open_sftp()
        with sftp.open('/tmp/insert_floor_plan.sql', 'w') as f:
            f.write(sql)
        sftp.close()

        stdin, stdout, stderr = ssh.exec_command(
            "docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres < /tmp/insert_floor_plan.sql"
        )
        print(f"  Insert result: {stdout.read().decode()}")
        print(f"  Error: {stderr.read().decode()}")

        # Step 5: Verify
        print("\nStep 4: Verifying VPS floor_plan_images...")
        stdin, stdout, stderr = ssh.exec_command(
            f"docker exec supabase_db_AlphaPos psql -U postgres -d postgres -c \"SELECT id, floor, image_filename, is_deleted FROM public.floor_plan_images WHERE merchant_id='{MERCHANT_ID}';\""
        )
        print(stdout.read().decode())

        # Step 6: Verify storage object
        print("Step 5: Verifying VPS storage objects...")
        stdin, stdout, stderr = ssh.exec_command(
            f"docker exec supabase_db_AlphaPos psql -U postgres -d postgres -c \"SELECT name, bucket_id FROM storage.objects WHERE name LIKE '%floor_plan%';\""
        )
        print(stdout.read().decode())

        # Step 7: Test public URL
        anon_token = make_token("anon")
        print("Step 6: Test download URL...")
        stdin, stdout, stderr = ssh.exec_command(
            f"curl -I -s 'http://localhost:54321/storage/v1/object/public/product-media/{OBJECT_PATH}' 2>&1 | head -5"
        )
        print(stdout.read().decode())

    except Exception as e:
        import traceback
        traceback.print_exc()
    finally:
        ssh.close()

if __name__ == "__main__":
    run()
