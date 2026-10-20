// Read-only verification; no migration or organization changes are applied.
import 'reflect-metadata';
import process from 'node:process';
import {Database} from '../src/common/database';
import {WorkspaceService} from '../src/workspace/workspace.service';
async function main(){
 process.loadEnvFile('.env');process.env.DATABASE_MIGRATE='false';process.env.DATABASE_SCHEMA='booking_app';process.env.DATABASE_SSL='true';process.env.DATABASE_CA_FILE='../.local/supabase-ca.crt';
 const db=new Database();
 try{
  await db.onModuleInit();
  const a=(await db.query<any>("SELECT user_id,email,display_name FROM memberships WHERE active=true AND role='owner' LIMIT 1")).rows[0];
  if(!a)throw new Error('No owner found');
  const d=await new WorkspaceService(db).organizationDetails({uid:a.user_id,email:a.email,name:a.display_name});
  if(!/^[a-f0-9]{64}$/.test(d.revision)||!d.locations.length)throw new Error('Invalid edit snapshot');
  const privileges=(await db.query<any>("SELECT has_table_privilege(current_user,'booking_app.organizations','UPDATE') AS organization_update,has_table_privilege(current_user,'booking_app.locations','UPDATE') AS location_update")).rows[0];
  if(!privileges.organization_update||!privileges.location_update)throw new Error('Existing server role cannot update the required tables');
  console.log(JSON.stringify({verified:true,revision_valid:true,locations:d.locations.length,existing_update_permissions:privileges,migration_required:false,live_data_changed:false}));
 }catch(e:any){console.error('Read-only organization verification failed:',e.code??e.name);process.exitCode=1;}finally{await db.onModuleDestroy();}
}
void main();
