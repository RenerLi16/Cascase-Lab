// Local synthetic harness only. Requires Playwright and a running mock backend.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({headless:true, ...(process.env.CHROME_BIN ? {executablePath:process.env.CHROME_BIN} : {})});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error' && /SCRIPT ERROR|Parse Error/.test(m.text())) errors.push(m.text());});
    await page.goto(process.argv[2] || 'http://127.0.0.1:8000/web-test/');
    await page.waitForFunction(()=>document.querySelector('#test-result')?.textContent.includes('ready-to-refresh'),null,{timeout:90000});
    const first = JSON.parse(await page.locator('#test-result').textContent());
    assert.deepEqual(first.failures,[]);
    const before = await page.evaluate(()=>Object.values(localStorage).filter(v=>v.startsWith('[{"')).map(v=>JSON.parse(v)).flat().filter(v=>v.session_id));
    const identities = before.map(s=>s.session_id).sort();
    assert.ok(before.every(s=>s.auth_flow==='public' && s.metadata.research_eligible===false && s.metadata.record_mode==='public-demo'));
    assert.ok(before.every(s=>s.credential.length===64));
    await page.reload();
    await page.waitForFunction(()=>document.querySelector('#test-result')?.textContent.includes('recovered'),null,{timeout:90000});
    const recovered = JSON.parse(await page.locator('#test-result').textContent());
    assert.deepEqual(recovered.failures,[]);
    const after = await page.evaluate(()=>Object.values(localStorage).filter(v=>v.startsWith('[{"')).map(v=>JSON.parse(v)).flat().filter(v=>v.session_id));
    assert.ok(after.every(s=>identities.includes(s.session_id)),'Refresh never creates or reassigns a session');
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({first,recovered,identities:identities.length,errors}));
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
