import paramiko
import io

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"

sql = """ALTER TABLE public.restaurant_tables 
ADD COLUMN IF NOT EXISTS is_round BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS table_shape VARCHAR(20) NOT NULL DEFAULT 'rectangle',
ADD COLUMN IF NOT EXISTS zone VARCHAR(100) DEFAULT 'Indoor';
"""

def run():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(hostname, username=username, password=password, timeout=10)
        
        # Copy SQL file via SFTP
        sftp = ssh.open_sftp()
        with sftp.open('/tmp/fix_tables.sql', 'w') as f:
            f.write(sql)
        sftp.close()
        print("SQL file uploaded to /tmp/fix_tables.sql")
        
        # Execute via psql using the file
        cmd_exec = "docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres < /tmp/fix_tables.sql"
        stdin, stdout, stderr = ssh.exec_command(cmd_exec)
        out = stdout.read().decode('utf-8')
        err = stderr.read().decode('utf-8')
        print("STDOUT:", out)
        print("STDERR:", err)
        
        # Verify columns
        cmd_verify = "docker exec supabase_db_AlphaPos psql -U postgres -d postgres -c \"SELECT column_name, data_type FROM information_schema.columns WHERE table_name='restaurant_tables' ORDER BY ordinal_position;\""
        stdin, stdout, stderr = ssh.exec_command(cmd_verify)
        print("COLUMNS:", stdout.read().decode('utf-8'))
    except Exception as e:
        import traceback
        print(f"Error: {e}")
        traceback.print_exc()
    finally:
        ssh.close()

if __name__ == "__main__":
    run()
