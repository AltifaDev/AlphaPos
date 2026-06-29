import paramiko
import sys

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"

def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print("Connecting to VPS...")
        ssh.connect(hostname, username=username, password=password, timeout=15)
        print("Connected.")

        # Find the db container
        stdin, stdout, stderr = ssh.exec_command("docker ps --filter name=db --format '{{.Names}}'")
        containers = stdout.read().decode().strip().split('\n')
        db_container = None
        for name in containers:
            if 'db' in name:
                db_container = name
                break
        
        if not db_container:
            # Fallback check
            stdin, stdout, stderr = ssh.exec_command("docker ps --format '{{.Names}}'")
            all_containers = stdout.read().decode().strip().split('\n')
            print("All containers:", all_containers)
            for name in all_containers:
                if 'db' in name or 'postgres' in name:
                    db_container = name
                    break
        
        if not db_container:
            print("Error: Could not find database container")
            return
            
        print(f"Using database container: {db_container}")
        
        # SQL migration commands
        sql = """
        BEGIN;
        
        -- Delete any orphaned modifier rows to prevent FK check failure
        DELETE FROM public.order_item_modifiers 
        WHERE order_item_id IS NOT NULL 
          AND order_item_id NOT IN (SELECT id FROM public.order_items);
          
        -- Re-add the FK constraint properly
        ALTER TABLE public.order_item_modifiers 
            DROP CONSTRAINT IF EXISTS order_item_modifiers_order_item_id_fkey;
            
        ALTER TABLE public.order_item_modifiers 
            ADD CONSTRAINT order_item_modifiers_order_item_id_fkey 
            FOREIGN KEY (order_item_id) 
            REFERENCES public.order_items(id) 
            ON DELETE CASCADE;
            
        COMMIT;
        """
        
        print("Running SQL migration in container...")
        # Escape single quotes and execute psql command
        escaped_sql = sql.replace("'", "'\\''")
        cmd = f"docker exec -i {db_container} psql -U postgres -d postgres -c '{escaped_sql}'"
        
        stdin, stdout, stderr = ssh.exec_command(cmd)
        out = stdout.read().decode()
        err = stderr.read().decode()
        
        print("Migration stdout:")
        print(out)
        if err:
            print("Migration stderr:")
            print(err)
            
    except Exception as e:
        print("Exception occurred:", e)
    finally:
        ssh.close()

if __name__ == "__main__":
    main()
