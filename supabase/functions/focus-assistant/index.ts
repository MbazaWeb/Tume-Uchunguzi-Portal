import "jsr:@supabase/functions-js/edge-runtime.d.ts";
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 const {text,mode,question,source,article}=await req.json();
 if(!text||String(text).length>1800)return Response.json({error:"Invalid selection"},{status:400});
 const key=Deno.env.get("OPENAI_API_KEY");
 if(!key)return Response.json({error:"AI service is not configured yet."},{status:503});
 const task=mode==="translate"?"Translate the selected Swahili text into clear English. Preserve legal meaning and do not add content.":mode==="simple"?"Explain the selected constitutional text in simple Kiswahili. Do not add rights, duties, or conclusions not stated in the text.":mode==="question"?`Answer this user's question using the selected constitutional text as the primary basis: "${String(question||"").slice(0,500)}". If the selected text does not support the answer, say so clearly. Do not invent constitutional provisions, give political advocacy, or present legal advice.`:"Analyze the selected constitutional text neutrally in Kiswahili: identify what it says, key terms, and any conditions or limits visible in the text. Do not give political advocacy or legal advice.";
 const prompt=`SOURCE DOCUMENT: ${source||""}\nARTICLE: ${article||""}\nSELECTED SOURCE TEXT:\n${text}\n\nTASK:\n${task}\n\nClearly label the answer as an AI explanation/translation, not source text.`;
 const res=await fetch("https://api.openai.com/v1/responses",{method:"POST",headers:{"Authorization":`Bearer ${key}`,"Content-Type":"application/json"},body:JSON.stringify({model:"gpt-5-mini",input:prompt,max_output_tokens:700})});
 if(!res.ok)return Response.json({error:"AI request failed."},{status:502});
 const data=await res.json();const output=data.output_text||data.output?.flatMap((x:any)=>x.content||[]).map((x:any)=>x.text||"").join("")||"";
 return Response.json({output});
});