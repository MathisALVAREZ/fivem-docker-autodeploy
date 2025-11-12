const overlay = document.getElementById('overlay')
const closeBtn = document.getElementById('close')
const amountInput = document.getElementById('amount')
const societyEl = document.getElementById('society')
const rateEl = document.getElementById('rate')
const taxEl = document.getElementById('tax')
const debtEl = document.getElementById('debt')
const infoEl = document.getElementById('info')
const weeklyBlock = document.getElementById('weeklyBlock')
const declareBtn = document.getElementById('declare')
const clearBtn = document.getElementById('clear')
const payDebtBtn = document.getElementById('payDebt')
const tbody = document.getElementById('tbody')

let CURRENT = { society:null, rate:0, weeklyBlocked:false }
let allHistory = []
let currentPage = 1
const pageSize = 5

/* ---------- UTIL ---------- */
const fmt = n => new Intl.NumberFormat('fr-FR').format(n||0)
const formatDate = v => new Date(v).toLocaleString('fr-FR',
  {year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'})

/* ---------- CALCUL ---------- */
function recalc(){
  const v = parseInt(amountInput.value||0,10)
  const tax = Math.floor(v * CURRENT.rate / 100)
  const debt = Math.floor(tax * 1.05)
  taxEl.textContent = '$'+fmt(tax)
  debtEl.textContent = '$'+fmt(debt)
}
amountInput.addEventListener('input',recalc)

/* ---------- NUI GÉNÉRAL ---------- */
closeBtn.onclick=()=>{ fetch(`https://${GetParentResourceName()}/close`,{method:'POST'}); overlay.style.display='none' }
clearBtn.onclick=()=>{ amountInput.value=''; recalc(); infoEl.textContent='' }

declareBtn.onclick=()=>{
  if(CURRENT.weeklyBlocked) return infoEl.textContent='Déjà déclaré cette semaine.'
  const v=parseInt(amountInput.value||0,10)
  const link=document.getElementById('accountingLink').value.trim()
  if(!v||v<=0) return infoEl.textContent='Montant invalide.'
  fetch(`https://${GetParentResourceName()}/declare`,{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({amount:v,society:CURRENT.society,link})
  }).then(()=>{ infoEl.textContent='Déclaration envoyée.'; amountInput.value=''; document.getElementById('accountingLink').value=''; recalc() })
}

/* ---------- HISTORIQUE ---------- */
function renderHistory(rows){ allHistory=rows||[]; currentPage=1; displayPage() }

function displayPage() {
  const search = document.getElementById('searchInput')?.value?.toLowerCase() || ''
  const filtered = allHistory.filter(r => formatDate(r.declaration_date).toLowerCase().includes(search))
  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  if (currentPage > totalPages) currentPage = totalPages

  const start = (currentPage - 1) * pageSize
  const pageRows = filtered.slice(start, start + pageSize)
  tbody.innerHTML = ''

  pageRows.forEach(r => {
    const dateTxt = formatDate(r.declaration_date)

    // ✅ statut paiement
    let statutHtml = r.paid == 1
      ? `<span class="stat-ok">Payé</span>`
      : `<div class="stat-nok">Non payé <button class="pay-btn" data-id="${r.id}">Régulariser</button></div>`

    // ✅ bouton fiche comptable à droite
    const ficheHtml = `
      <button class="doc-btn" data-id="${r.id}">
        📘 Envoyer la fiche
      </button>
    `

    const tr = document.createElement('div')
    tr.className = 'history-row'
    tr.innerHTML = `
      <div>${dateTxt}</div>
      <div>$${fmt(r.declared_amount)}</div>
      <div>$${fmt(r.tax_amount)}</div>
      <div>$${fmt(r.debt_amount || 0)}</div>
      <div>${statutHtml} ${ficheHtml}</div>
    `
    tbody.appendChild(tr)
  })

  document.getElementById('pageInfo').textContent = `${currentPage}/${Math.max(1, Math.ceil(filtered.length / pageSize))}`
}


/* ---------- PAGINATION ---------- */
document.getElementById('searchInput').oninput=()=>{currentPage=1;displayPage()}
document.getElementById('prevPage').onclick=()=>{if(currentPage>1){currentPage--;displayPage()}}
document.getElementById('nextPage').onclick=()=>{currentPage++;displayPage()}

/* ---------- PAYER TOUT ---------- */
payDebtBtn.onclick=()=>{
  fetch(`https://${GetParentResourceName()}/payDebt`,{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({society:CURRENT.society})
  }).then(r=>r.json().then(d=>infoEl.textContent=d.msg||'Requête envoyée.'))
}

/* ---------- TABS ---------- */
document.addEventListener("DOMContentLoaded", () => {
  const tabs = document.querySelectorAll('.tab');
  const contents = document.querySelectorAll('.tab-content');
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      contents.forEach(c => c.classList.remove('active'));
      tab.classList.add('active');
      const target = tab.dataset.tab;
      document.getElementById(`tab-${target}`).classList.add('active');
    });
  });
});

/* ---------- MESSAGE EVENTS ---------- */
window.addEventListener('message',e=>{
  const d=e.data||{}
  if(d.action==='open'){ overlay.style.display='flex'; CURRENT={society:d.society,rate:d.rate,weeklyBlocked:!!d.weeklyBlocked};
    societyEl.textContent=d.society; rateEl.textContent=d.rate+' %'; weeklyBlock.style.display=d.weeklyBlocked?'block':'none'; renderHistory(d.history||[]); recalc()
  }else if(d.action==='updateHistory'){ renderHistory(d.history||[]) }
  else if(d.action==='alreadyDeclared'){ showAlert(d.message) }
  else if(d.action==='debtPaid'){ updateRowAsPaid(d.id,d.success) }
})

/* ---------- ALERTES ---------- */
function showAlert(msg){
  const box=document.createElement('div')
  box.className='alertBox'; box.innerHTML=`<span>⚠️</span> ${msg}`
  document.body.appendChild(box); setTimeout(()=>box.remove(),4000)
}
function updateRowAsPaid(id,success){
  const row=document.querySelector(`.pay-btn[data-id="${id}"]`)?.closest('div')?.parentElement
  if(!row) return
  if(!success){ return }
  row.children[3].textContent='$0'
  row.children[4].innerHTML=`<span class="stat-ok">Payé</span>`
}

/* =========================================================
   📘 Envoi de la fiche comptable (webhook Discord)
   ========================================================= */
// === Bouton "Envoyer fiche" (envoi direct vers le serveur) ===
document.addEventListener('click', (event) => {
  const btn = event.target.closest('.doc-btn')
  if (!btn) return

  const declId = btn.dataset.id
  if (!declId) return

  fetch(`https://${GetParentResourceName()}/sendAccountingLink`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: parseInt(declId) })
  })

  showEvogenNotif("📨 Fiche comptable envoyée sur Discord !")
})


/* ---------- Notification stylée Evogen ---------- */
function showEvogenNotif(text) {
  const notif = document.createElement('div')
  notif.className = 'evogen-notif'
  notif.textContent = text
  document.body.appendChild(notif)
  notif.animate([
    { opacity: 0, transform: "translate(-50%, 20px)" },
    { opacity: 1, transform: "translate(-50%, 0)" }
  ], { duration: 400, easing: "ease-out" })
  setTimeout(() => notif.remove(), 4000)
}

