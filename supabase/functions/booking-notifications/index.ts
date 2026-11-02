import R from"node:process";import{Buffer as B}from"node:buffer";var g=`-----BEGIN CERTIFICATE-----
MIIDxDCCAqygAwIBAgIUbLxMod62P2ktCiAkxnKJwtE9VPYwDQYJKoZIhvcNAQEL
BQAwazELMAkGA1UEBhMCVVMxEDAOBgNVBAgMB0RlbHdhcmUxEzARBgNVBAcMCk5l
dyBDYXN0bGUxFTATBgNVBAoMDFN1cGFiYXNlIEluYzEeMBwGA1UEAwwVU3VwYWJh
c2UgUm9vdCAyMDIxIENBMB4XDTIxMDQyODEwNTY1M1oXDTMxMDQyNjEwNTY1M1ow
azELMAkGA1UEBhMCVVMxEDAOBgNVBAgMB0RlbHdhcmUxEzARBgNVBAcMCk5ldyBD
YXN0bGUxFTATBgNVBAoMDFN1cGFiYXNlIEluYzEeMBwGA1UEAwwVU3VwYWJhc2Ug
Um9vdCAyMDIxIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqQXW
QyHOB+qR2GJobCq/CBmQ40G0oDmCC3mzVnn8sv4XNeWtE5XcEL0uVih7Jo4Dkx1Q
DmGHBH1zDfgs2qXiLb6xpw/CKQPypZW1JssOTMIfQppNQ87K75Ya0p25Y3ePS2t2
GtvHxNjUV6kjOZjEn2yWEcBdpOVCUYBVFBNMB4YBHkNRDa/+S4uywAoaTWnCJLUi
cvTlHmMw6xSQQn1UfRQHk50DMCEJ7Cy1RxrZJrkXXRP3LqQL2ijJ6F4yMfh+Gyb4
O4XajoVj/+R4GwywKYrrS8PrSNtwxr5StlQO8zIQUSMiq26wM8mgELFlS/32Uclt
NaQ1xBRizkzpZct9DwIDAQABo2AwXjALBgNVHQ8EBAMCAQYwHQYDVR0OBBYEFKjX
uXY32CztkhImng4yJNUtaUYsMB8GA1UdIwQYMBaAFKjXuXY32CztkhImng4yJNUt
aUYsMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAB8spzNn+4VU
tVxbdMaX+39Z50sc7uATmus16jmmHjhIHz+l/9GlJ5KqAMOx26mPZgfzG7oneL2b
VW+WgYUkTT3XEPFWnTp2RJwQao8/tYPXWEJDc0WVQHrpmnWOFKU/d3MqBgBm5y+6
jB81TU/RG2rVerPDWP+1MMcNNy0491CTL5XQZ7JfDJJ9CCmXSdtTl4uUQnSuv/Qx
Cea13BX2ZgJc7Au30vihLhub52De4P/4gonKsNHYdbWjg7OWKwNv/zitGDVDB9Y2
CMTyZKG3XEu5Ghl1LEnI3QmEKsqaCLv12BnVjbkSeZsMnevJPs1Ye6TjjJwdik5P
o/bKiIz+Fq8=
-----END CERTIFICATE-----
`;import{Pool as T}from"npm:pg@8.16.3";var l=class{pool;connection(){if(this.pool)return this.pool;let e=process.env.BOOKING_DATABASE_URL,t=process.env.BOOKING_DATABASE_CA??g;if(!e||!t)throw new Error("Cloud database is not configured");let i=new URL(e);if(!i.hostname.endsWith(".pooler.supabase.com"))throw new Error("Expected Supabase pooler");for(let o of["sslmode","sslcert","sslkey","sslrootcert"])i.searchParams.delete(o);return this.pool=new T({connectionString:i.toString(),max:2,ssl:{rejectUnauthorized:!0,ca:t},options:"-c search_path=booking_app,pg_catalog -c statement_timeout=20000 -c lock_timeout=10000",connectionTimeoutMillis:1e4,idleTimeoutMillis:1e4}),this.pool.on("error",()=>console.error("Idle cloud database connection failed")),this.pool}async query(e,t=[]){return{rows:(await this.connection().query(e,t)).rows}}async transaction(e){let t=await this.connection().connect();try{await t.query("BEGIN");let i=await e({query:async(o,r=[])=>({rows:(await t.query(o,r)).rows})});return await t.query("COMMIT"),i}catch(i){throw await t.query("ROLLBACK"),i}finally{t.release()}}async close(){await this.pool?.end()}};import{createSign as O}from"node:crypto";function h(n){if(!Number.isSafeInteger(n?.amount_minor)||n.amount_minor<0||!/^[A-Z]{3}$/.test(n.currency))throw new Error("Invalid subscription fee snapshot");return`Collect ${new Intl.NumberFormat("en-IN",{style:"currency",currency:n.currency}).format(n.amount_minor/100)} from ${d(n.customer_name,"a subscriber")} for this month at ${d(n.space_name,"the space")}.`}function E(n,e){if(!Number.isSafeInteger(n?.amount_minor)||n.amount_minor<=0||!Number.isSafeInteger(n.balance_after_minor)||n.balance_after_minor<0||!/^[A-Z]{3}$/.test(n.currency))throw new Error("Invalid cash notification snapshot");let t=i=>new Intl.NumberFormat("en-IN",{style:"currency",currency:n.currency}).format(i/100);return`${e?`${d(n.collector_name,"The owner")} collected`:"You collected"} ${t(n.amount_minor)} from ${e?"you":d(n.staff_name,"staff")}.
Remaining to hand over: ${t(n.balance_after_minor)}.`}function d(n,e){if(typeof n!="string")return e;let t=n.replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/gu," ").replace(/\s+/gu," ").trim();return Array.from(t).slice(0,80).join("")||e}function I(n){if(!n.starts_at||!n.timezone)return"Time unavailable";let e=new Date(n.starts_at);if(!Number.isFinite(e.getTime()))return"Time unavailable";try{let t=new Intl.DateTimeFormat("en-IN",{timeZone:n.timezone,day:"numeric",month:"short",year:"numeric"}),i=new Intl.DateTimeFormat("en-IN",{timeZone:n.timezone,hour:"numeric",minute:"2-digit",hour12:!0,timeZoneName:"short"}),o=_=>i.format(_).replace(/\s+/gu," ").replace(/\b(am|pm)\b/gi,m=>m.toUpperCase()),r=`${t.format(e)}, ${o(e)}`,s=n.ends_at?new Date(n.ends_at):null;if(!s||!Number.isFinite(s.getTime())||s<=e)return r;let c=t.format(s);return`${r} \u2013 ${c===t.format(e)?"":`${c}, `}${o(s)}`}catch{return"Time unavailable"}}function b(n,e){let t=d(n,"Booking");return e?[`Name: ${d(e.customer_name,"Customer")}`,`Space: ${d(e.space_name,"Booked space")}`,`Time: ${I(e)}`,t].join(`
`):`Booking ${t}. Open Booking OS for details.`}var a=class extends Error{constructor(t,i,o=!1,r=0){super(t);this.code=t;this.retryable=i;this.unregistered=o;this.retryAfterSeconds=r}},u=class{constructor(e=fetch){this.http=e}access;refreshing;credentials(){try{let e=JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON??"{}");if(typeof e.project_id!="string"||!/^[a-z][a-z0-9-]+$/.test(e.project_id)||typeof e.client_email!="string"||typeof e.private_key!="string")throw new Error;return e}catch{throw new a("FCM_CREDENTIALS",!0,!1,300)}}async accessToken(){if(this.access&&this.access.expires>Date.now()+6e4)return this.access.token;if(this.refreshing)return this.refreshing;this.refreshing=this.mintToken();try{return await this.refreshing}finally{this.refreshing=void 0}}async mintToken(){try{let e=this.credentials(),t=Math.floor(Date.now()/1e3),i=_=>Buffer.from(JSON.stringify(_)).toString("base64url"),o=`${i({alg:"RS256",typ:"JWT"})}.${i({iss:e.client_email,scope:"https://www.googleapis.com/auth/firebase.messaging",aud:"https://oauth2.googleapis.com/token",iat:t,exp:t+3600})}`,r=O("RSA-SHA256").update(o).sign(e.private_key,"base64url"),s=await this.http("https://oauth2.googleapis.com/token",{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion:`${o}.${r}`}),signal:AbortSignal.timeout(1e4)});if(!s.ok)throw new a("FCM_OAUTH",!0,!1,300);let c=await s.json();if(!c.access_token||!c.expires_in)throw new a("FCM_OAUTH",!0,!1,300);return this.access={token:c.access_token,expires:Date.now()+c.expires_in*1e3},c.access_token}catch(e){throw e instanceof a?e:new a("FCM_OAUTH",!0,!1,300)}}async send(e){let t={created:"Order placed",cancelled:"Order cancelled",rescheduled:"Order rescheduled",staff_cash_collected:"Cash collection confirmed",subscription_fee_due:"Subscription fee due"}[e.kind];if(!t)throw new a("INVALID_EVENT",!1);let i;try{if(e.kind==="staff_cash_collected"&&!e.settlementId)throw new Error;if(e.kind==="subscription_fee_due"&&!e.admissionId)throw new Error;i=e.kind==="staff_cash_collected"?E(e.cashDetails,e.forStaff===!0):e.kind==="subscription_fee_due"?h(e.feeDetails):b(e.reference,e.details)}catch{throw new a("INVALID_EVENT",!1)}let o=this.credentials(),r=await this.accessToken(),s;try{s=await this.http(`https://fcm.googleapis.com/v1/projects/${o.project_id}/messages:send`,{method:"POST",headers:{authorization:`Bearer ${r}`,"content-type":"application/json"},signal:AbortSignal.timeout(1e4),body:JSON.stringify({message:{token:e.token,notification:{title:t,body:i},data:{event_id:e.eventId,...e.kind==="staff_cash_collected"?{settlement_id:e.settlementId}:e.kind==="subscription_fee_due"?{admission_id:e.admissionId}:{booking_id:e.bookingId},event_type:e.kind,recipient_user_id:e.userId},android:{priority:"high",ttl:"86400s",notification:{channel_id:"booking_orders_bell_v2",sound:"new_booking_bell",icon:"ic_stat_booking",tag:e.eventId}},apns:{headers:{"apns-priority":"10","apns-expiration":String(Math.floor(Date.now()/1e3)+86400)},payload:{aps:{sound:"default","thread-id":"booking_orders"}}}}})})}catch{throw new a("FCM_NETWORK",!0)}if(s.ok)return;if((await s.json().catch(()=>({}))).error?.details?.find(w=>w["@type"]==="type.googleapis.com/google.firebase.fcm.v1.FcmError")?.errorCode==="UNREGISTERED")throw new a("UNREGISTERED",!1,!0);s.status===401&&(this.access=void 0);let m=s.status===429||s.status>=500||s.status===401||s.status===403,f=s.headers.get("retry-after"),N=f?Number(f)||Math.max(0,(Date.parse(f)-Date.now())/1e3):0;throw new a(`FCM_HTTP_${s.status}`,m,!1,Number.isFinite(N)?Math.min(N,3600):0)}};import{randomUUID as v}from"node:crypto";var y=`jsonb_build_object(
  'customer_name',b.customer_snapshot->>'name',
  'space_name',b.price_snapshot->>'space_name',
  'starts_at',b.starts_at,'ends_at',b.ends_at,
  'timezone',b.price_snapshot->>'timezone')`;var D=`m.active AND m.user_id=d.user_id AND m.organization_id=e.organization_id
 AND m.user_id NOT LIKE 'sarvam:%'
 AND (
  (e.kind='staff_cash_collected' AND s.id IS NOT NULL AND s.direction='collect' AND
   ((m.user_id=s.settled_by AND m.role='owner') OR
    (m.id=s.membership_id AND m.role<>'owner' AND (m.permissions ? 'collect_payments' OR m.permissions ? 'view_finance'))))
  OR
  (e.kind='subscription_fee_due' AND (m.role='owner' OR (m.permissions ? 'collect_payments' AND EXISTS (
    SELECT 1 FROM staff_assignments a WHERE a.membership_id=m.id AND a.business_id=e.business_id
    AND a.organization_id=e.organization_id AND (jsonb_array_length(a.resource_ids)=0 OR a.resource_ids ? e.resource_id::text)))))
  OR
  (e.kind NOT IN ('staff_cash_collected','subscription_fee_due') AND (m.role='owner' OR (m.permissions ? 'manage_bookings' AND EXISTS (
    SELECT 1 FROM staff_assignments a WHERE a.membership_id=m.id AND a.business_id=e.business_id
    AND a.organization_id=e.organization_id AND (jsonb_array_length(a.resource_ids)=0 OR a.resource_ids ? e.resource_id::text)))))
 )`,p=class{constructor(e,t){this.db=e;this.sender=t}async dispatch(e=20){e=Math.max(1,Math.min(40,Math.floor(e)));try{await this.queueFees()}catch{console.error(JSON.stringify({event:"subscription_fee_queue_failed"}))}await this.expand(e);let t=v(),i=await this.db.transaction(async r=>(await r.query(`UPDATE notification_deliveries SET state='dead',last_error='ATTEMPTS_EXHAUSTED',lease_id=NULL,lease_until=NULL
        WHERE state IN ('pending','processing') AND attempts>=8 AND (lease_until IS NULL OR lease_until<now())`),(await r.query(`WITH pending AS (
        SELECT event_id,device_id FROM notification_deliveries
        WHERE attempts<8 AND ((state='pending' AND next_attempt_at<=now()) OR (state='processing' AND lease_until<now()))
        ORDER BY next_attempt_at,event_id,device_id FOR UPDATE SKIP LOCKED LIMIT $1
      ) UPDATE notification_deliveries n SET state='processing',attempts=n.attempts+1,lease_id=$2,lease_until=now()+interval '3 minutes'
        FROM pending p WHERE n.event_id=p.event_id AND n.device_id=p.device_id
        RETURNING n.event_id,n.device_id,n.recipient_user_id`,[e,t])).rows)),o={claimed:i.length,sent:0,skipped:0,retry:0,dead:0};for(let r=0;r<i.length;r+=4)await Promise.all(i.slice(r,r+4).map(async s=>{let c=await this.deliver(s,t);o[c]++}));return o}async queueFees(){await this.db.query(`INSERT INTO booking_notification_events(id,organization_id,business_id,resource_id,kind,reference,admission_id,due_on,fee_details)
      SELECT gen_random_uuid(),a.organization_id,a.business_id,a.resource_id,'subscription_fee_due',a.reference,a.id,(i->>'due_on')::date,
        jsonb_build_object('customer_name',a.customer_snapshot->>'name','space_name',r.name,
          'amount_minor',(i->>'amount_minor')::integer,'currency',o.currency,'due_on',i->>'due_on')
      FROM admissions a JOIN resources r ON r.id=a.resource_id JOIN organizations o ON o.id=a.organization_id
      CROSS JOIN LATERAL jsonb_array_elements(a.plan_snapshot->'subscription'->'instalments') i
      WHERE a.plan_snapshot ? 'subscription' AND NOT a.cancelled AND a.deleted_at IS NULL
        AND a.expires_on>=current_date-1
        AND (i->>'due_on')::date=(now() AT TIME ZONE a.timezone)::date AND (i->>'due_on')::date>a.starts_on
      ON CONFLICT(admission_id,due_on) DO NOTHING`)}async expand(e){await this.db.transaction(async t=>{let i=(await t.query("SELECT id FROM booking_notification_events WHERE NOT expanded ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT $1",[e])).rows;for(let o of i)await t.query(`INSERT INTO notification_deliveries(event_id,device_id,recipient_user_id)
          SELECT e.id,d.id,d.user_id FROM booking_notification_events e
          LEFT JOIN staff_cash_settlements s ON s.id=e.settlement_id AND s.organization_id=e.organization_id
          JOIN notification_devices d ON d.enabled AND d.bound_at<=e.created_at AND d.last_seen_at>now()-interval '60 days'
          JOIN memberships m ON m.user_id=d.user_id
          WHERE e.id=$1 AND e.created_at>now()-interval '24 hours' AND ${D}
          ON CONFLICT(event_id,device_id) DO NOTHING`,[o.id]),await t.query("UPDATE booking_notification_events SET expanded=true WHERE id=$1",[o.id])})}async deliver(e,t){let i=(await this.db.query(`SELECT d.token,d.version,e.kind,e.reference,e.booking_id,e.settlement_id,e.admission_id,e.cash_details,e.fee_details,(m.id=s.membership_id) AS for_staff,
        COALESCE(h.details->'notification',CASE WHEN b.resource_id=e.resource_id
          THEN ${y} END) AS details
      FROM notification_deliveries n JOIN booking_notification_events e ON e.id=n.event_id
      LEFT JOIN staff_cash_settlements s ON s.id=e.settlement_id AND s.organization_id=e.organization_id
      LEFT JOIN booking_history h ON h.id=e.history_id
      LEFT JOIN bookings b ON b.id=e.booking_id AND b.organization_id=e.organization_id
      LEFT JOIN admissions ad ON ad.id=e.admission_id AND ad.organization_id=e.organization_id
        AND NOT ad.cancelled AND ad.deleted_at IS NULL
      JOIN notification_devices d ON d.id=n.device_id
      JOIN memberships m ON m.user_id=d.user_id
      WHERE n.event_id=$1 AND n.device_id=$2 AND n.lease_id=$3 AND n.state='processing'
      AND d.enabled AND n.recipient_user_id=d.user_id AND d.bound_at<=e.created_at
      AND d.last_seen_at>now()-interval '60 days' AND e.created_at>now()-interval '24 hours'
      AND (e.kind='staff_cash_collected' OR b.id IS NOT NULL OR ad.id IS NOT NULL) AND ${D}`,[e.event_id,e.device_id,t])).rows[0];if(!i)return await this.finish(e,t,"skipped","INELIGIBLE_OR_EXPIRED"),"skipped";try{return await this.sender.send({token:i.token,eventId:e.event_id,bookingId:i.booking_id,settlementId:i.settlement_id,admissionId:i.admission_id,cashDetails:i.cash_details,feeDetails:i.fee_details,forStaff:i.for_staff,userId:e.recipient_user_id,kind:i.kind,reference:i.reference,details:i.details}),await this.finish(e,t,"sent",""),"sent"}catch(o){let r=o instanceof a?o:new a("SEND_FAILED",!0);r.unregistered&&await this.db.query("UPDATE notification_devices SET enabled=false,version=version+1,updated_at=now() WHERE id=$1 AND version=$2",[e.device_id,i.version]);let s=r.retryable?"pending":"dead";return(await this.db.query(`UPDATE notification_deliveries SET
        state=CASE WHEN attempts>=8 THEN 'dead' ELSE $4 END,last_error=$5,
        next_attempt_at=now()+make_interval(secs=>GREATEST($6::integer,LEAST(3600,30*power(2,attempts-1)::integer))),
        lease_id=NULL,lease_until=NULL
        WHERE event_id=$1 AND device_id=$2 AND lease_id=$3 AND state='processing' RETURNING state`,[e.event_id,e.device_id,t,s,r.code,Math.ceil(r.retryAfterSeconds)])).rows[0]?.state==="pending"?"retry":"dead"}}async finish(e,t,i,o){await this.db.query(`UPDATE notification_deliveries SET state=$4,last_error=$5,accepted_at=CASE WHEN $4='sent' THEN now() ELSE NULL END,
      lease_id=NULL,lease_until=NULL WHERE event_id=$1 AND device_id=$2 AND lease_id=$3 AND state='processing'`,[e.event_id,e.device_id,t,i,o])}};import{createHash as k,timingSafeEqual as S}from"node:crypto";function A(n){return async e=>{let t={"cache-control":"no-store","content-type":"application/json"};if(e.method!=="POST")return new Response('{"error":"METHOD_NOT_ALLOWED"}',{status:405,headers:t});let i=process.env.BOOKING_PUSH_DISPATCH_SECRET,o=e.headers.get("x-booking-push-secret")??"",r=s=>k("sha256").update(s).digest();if(!i||i.length<32||!S(r(i),r(o)))return new Response('{"error":"UNAUTHORIZED"}',{status:401,headers:t});if(process.env.BOOKING_PUSH_DISPATCH_ENABLED!=="true")return new Response('{"disabled":true}',{status:200,headers:t});try{let s=await n.dispatch(20);return console.info(JSON.stringify({event:"booking_push_dispatch",...s})),Response.json(s,{headers:t})}catch{return console.error(JSON.stringify({event:"booking_push_dispatch_failed"})),new Response('{"error":"DISPATCH_FAILED"}',{status:503,headers:t})}}}Object.assign(globalThis,{process:R,Buffer:B});var C=new l,L=A(new p(C,new u));Deno.env.get("BOOKING_EDGE_TEST")!=="true"&&Deno.serve(L);export{L as handler};
