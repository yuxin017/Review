from __future__ import annotations
import hashlib, shutil, subprocess, sys
from pathlib import Path
from datetime import datetime

ROOT=Path.cwd().resolve()
HERE=Path(__file__).resolve().parent
BRANCH='fix/staff-coverage-timetable'

def replace(text,old,new,path):
    num=text.count(old)
    if num!=1:raise RuntimeError(f'{path}: expected one match, got {num} for {old[:90]!r}. NO FILES MODIFIED.')
    return text.replace(old,new,1)

def main():
    if not (ROOT/'lib/admin/staff/staff_schedule_arrangement.dart').exists():
        raise RuntimeError('Run from FYP_New project root.')
    branch=subprocess.run(['git','branch','--show-current'],capture_output=True,text=True,check=True).stdout.strip()
    if branch != BRANCH:raise RuntimeError(f'Wrong branch: {branch}. Expected {BRANCH}.')
    paths={n:ROOT/n for n in [
        'lib/admin/products/park_menu_management_page.dart',
        'lib/visitor/pages/home_page.dart',
        'lib/photos/photo_checkout_pages.dart',
        'functions/src/photos.js',
        'functions/local_stripe_server.cjs',
        'server/start-accounts.cjs',
        'tool/Start_Local_Stripe_Server.ps1',
        'firestore.rules',
    ]}
    additions=[
        'functions/src/stripe_commerce_gateway.js',
        'lib/commerce/stripe_commerce_client.dart',
        'lib/visitor/pages/souvenir_shop_page.dart',
    ]
    # This ZIP was designed to be unpacked INTO the project root. In that
    # layout, its three new source files already exist before patching.
    # Treat exact package matches as staged files, never overwrite other work.
    expected_additions={
        'functions/src/stripe_commerce_gateway.js': '0e99dd7edb7164f3a6cd829b3e07530e93661cf9d774e9310fc5d60c9bb53dc1',
        'lib/commerce/stripe_commerce_client.dart': '3723716d2a4cf9cd4bc365c492834062398c303c5ddef41a50ddc6a6ccd994e8',
        'lib/visitor/pages/souvenir_shop_page.dart': 'e43877c2f4852e0f2cc924357da55e998757deb67d09137afed721dcb8666568',
    }
    staged={}
    for name in additions:
        dest=ROOT/name
        source=dest if dest.exists() else HERE/'commerce_payload'/name
        if not source.is_file():
            raise RuntimeError(f'Missing {name}. Re-extract the FIXED ZIP without deleting your existing files.')
        actual=hashlib.sha256(source.read_bytes()).hexdigest()
        if actual!=expected_additions[name]:
            raise RuntimeError(
                f'{name} differs from the distributed package; refusing to overwrite user work. '
                'Back up/reconcile this file before retrying.'
            )
        staged[name]=source
    original={}; updated={}; metadata={}
    for name,f in paths.items():
        raw=f.read_bytes(); original[name]=raw
        metadata[name]=('\r\n' if b'\r\n' in raw else '\n',raw.startswith(b'\xef\xbb\xbf'))
        updated[name]=raw.decode('utf-8-sig').replace('\r\n','\n')
    def ch(p,a,b):updated[p]=replace(updated[p],a,b,p)

    # 1: Dynamic admin inventory. Existing products remain in parkMenuItems.
    p='lib/admin/products/park_menu_management_page.dart'
    ch(p,
        "    final price = TextEditingController(text: item?['priceMinor'] is num\n        ? ((item!['priceMinor'] as num) / 100).toStringAsFixed(2) : '');\n",
        "    final price = TextEditingController(text: item?['priceMinor'] is num\n        ? ((item!['priceMinor'] as num) / 100).toStringAsFixed(2) : '');\n"
        "    final stock = TextEditingController(text: (item?['stockQuantity'] as num?)?.toInt().toString() ?? '0');\n")
    ch(p,
        "          const SizedBox(height: 18),\n          Container(\n            decoration: BoxDecoration(\n              color: const Color(0xFFF8F1F0),\n",
        "           const SizedBox(height: 14),\n"
        "           if (!isDining) ...[\n"
        "             const Text('Inventory quantity *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),\n"
        "             const SizedBox(height: 8),\n"
        "             TextFormField(controller: stock, enabled: !saving,\n"
        "               keyboardType: TextInputType.number,\n"
        "               inputFormatters: [FilteringTextInputFormatter.digitsOnly],\n"
        "               decoration: const InputDecoration(hintText: 'e.g. 50'),\n"
        "               validator: (v) { final n = int.tryParse(v ?? '');\n"
        "                 return n == null || n < 0 || n > 1000000 ? 'Enter stock from 0 to 1,000,000.' : null;\n"
        "               }),\n"
        "             const SizedBox(height: 16),\n"
        "           ],\n"
        "          const SizedBox(height: 18),\n          Container(\n            decoration: BoxDecoration(\n              color: const Color(0xFFF8F1F0),\n")
    ch(p,
        "                    'priceMinor': parseMoneyMinor(price.text)!,\n                    'currency': 'MYR',\n",
        "                    'priceMinor': parseMoneyMinor(price.text)!,\n                    if (!isDining) 'stockQuantity': int.parse(stock.text),\n                    'currency': 'MYR',\n")
    ch(p,
        "                            '${entry.data()['active'] == true ? 'Available' : 'Unavailable'}'),\n",
        "                            '${entry.data()['active'] == true ? 'Available' : 'Unavailable'}'\n"
        "                             '${!dining ? ' · Stock: ${(entry.data()['stockQuantity'] as num?)?.toInt() ?? 0}' : ''}'),\n")

    # 2: Visitor Home entry to live Firestore product catalogue.
    p='lib/visitor/pages/home_page.dart'
    ch(p,"import '../../park/offers_page.dart';\n",
        "import '../../park/offers_page.dart';\nimport 'souvenir_shop_page.dart';\n")
    ch(p,
        "        _HomeShortcut(Icons.local_offer_outlined, 'Park Offers',\n",
        "        _HomeShortcut(Icons.shopping_bag_outlined, 'Souvenir Shop',\n"
        "          'Browse park merchandise',\n"
        "          () => Navigator.push(context, MaterialPageRoute(\n"
        "            builder: (_) => const SouvenirShopPage()))),\n"
        "        _HomeShortcut(Icons.local_offer_outlined, 'Park Offers',\n")

    # 3: Photo checkout: public requests can no longer create positive-amount paid orders.
    p='functions/src/photos.js'
    ch(p,'  async function checkout(request){\n',
        '  async function checkout(request, verifiedStripe=false){\n')
    ch(p,
        "      const value=await price(tx,request,items);\n      if(value.totalMinor!==request.data.expectedTotalMinor)",
        "      const value=await price(tx,request,items);\n"
        "      if(value.totalMinor>0&&!verifiedStripe)fail('failed-precondition','Complete secure Stripe payment before receiving purchased photos.');\n"
        "      if(value.totalMinor!==request.data.expectedTotalMinor)")
    ch(p,
        'favorite,claim,quote,checkout,purchaseState,download,',
        'favorite,claim,quote,checkout,checkoutPaid:request=>checkout(request,true),purchaseState,download,')
    # Prevent trusted server-only fulfillment method from becoming a callable client endpoint.
    # Legacy direct ticket checkout must also not issue passes without Stripe.
    p='server/start-accounts.cjs'
    ch(p,
       "for(const [name,handler]of Object.entries(ticketPromotions))operations['/v1/tickets/'+name]=handler;",
       "for(const [name,handler]of Object.entries(ticketPromotions))if(name!=='checkout')operations['/v1/tickets/'+name]=handler;")
    ch(p,
       "for(const [name,handler]of Object.entries(photos))if(name!=='runMatchingJobs')operations['/v1/photos/'+name]=handler;",
       "for(const [name,handler]of Object.entries(photos))if(!['runMatchingJobs','checkoutPaid'].includes(name))operations['/v1/photos/'+name]=handler;")

    # 4: Stripe local server: Ticket remains existing verified flow, Commerce shares signed webhook.
    p='functions/local_stripe_server.cjs'
    ch(p,"const {createStripeGateway} = require('./src/stripe_ticket_gateway');\n",
       "const {createStripeGateway,verifyStripeEvent} = require('./src/stripe_ticket_gateway');\n"
       "const {createCommerceStripeGateway} = require('./src/stripe_commerce_gateway');\n"
       "const {createPhotoHandlers} = require('./src/photos');\n")
    ch(p,
       "const port = Number(process.env.LOCAL_STRIPE_PORT || 8787);",
       "const port = Number(process.env.LOCAL_STRIPE_PORT || 8788);")
    ch(p,
       "const handlers = {\n",
       "const commerce=createCommerceStripeGateway({db:getFirestore(),FieldValue,projectId,\n"
       "  photos:createPhotoHandlers({db:getFirestore(),FieldValue,\n"
       "    ai:{call:async()=>{throw new Error('Photo rendering uses the main Node server.');}},\n"
       "    mailReady:()=>true}),\n"
       "  getStripeKey:()=>process.env.STRIPE_SECRET_KEY,\n"
       "});\nconst handlers = {\n"
       "  '/stripeSouvenirQuote':commerce.quote,\n"
       "  '/stripeCommerceCheckout':commerce.start,\n"
       "  '/stripeCommerceStatus':commerce.status,\n")
    ch(p,
       "      const raw=await readBuffer(req);\n      const webhookReq={method:req.method,headers:req.headers,rawBody:raw};",
       "      const raw=await readBuffer(req);\n"
       "      // Signature verification MUST occur before any payment/order mutation.\n"
       "      const event=verifyStripeEvent(raw,req.headers['stripe-signature'],process.env.STRIPE_WEBHOOK_SECRET);\n"
       "      const session=event.data?.object;\n"
       "      if(['souvenir','photo'].includes(session?.metadata?.checkoutType)) {\n"
       "        if(['checkout.session.completed','checkout.session.async_payment_succeeded'].includes(event.type) && session.payment_status==='paid') {\n"
       "          await commerce.fulfill(session);\n"
       "        } else if(event.type==='checkout.session.expired') {\n"
       "          await commerce.expired(session);\n"
       "        }\n"
       "        reply(res,200,{received:true});return;\n"
       "      }\n"
       "      const webhookReq={method:req.method,headers:req.headers,rawBody:raw};")
    # Stripe webhooks with no matching custom metadata still go to ticket handler.
    p='tool/Start_Local_Stripe_Server.ps1'
    ch(p,'node .\\local_stripe_server.cjs',
       "$env:LOCAL_STRIPE_PORT = '8788'\n  node .\\local_stripe_server.cjs")

    # 5: Firestore: visitor can read public catalogue. Admin remains sole catalog writer.
    p='firestore.rules'
    ch(p,
       "      return d.keys().hasOnly(['storeId','name','description','category',\n        'priceMinor','currency','active','imageUrl','createdAt','updatedAt'])",
       "      return d.keys().hasOnly(['storeId','name','description','category',\n        'priceMinor','currency','active','imageUrl','stockQuantity','createdAt','updatedAt'])")
    ch(p,
       "        && d.priceMinor is int && d.priceMinor >= 1 && d.priceMinor <= 10000000\n",
       "        && d.priceMinor is int && d.priceMinor >= 1 && d.priceMinor <= 10000000\n"
       "        && (d.get('stockQuantity', null) == null ||\n"
       "          (d.stockQuantity is int && d.stockQuantity >= 0 && d.stockQuantity <= 1000000))\n")
    ch(p,
       '    match /parkMenuItems/{itemId} {\n      allow get, list: if isAdmin();\n',
       '    match /parkMenuItems/{itemId} {\n      allow get, list: if signedIn(); // Public product catalogue only; no owner data.\n')
    # Commerce orders visible only to owner/admin; only backend creates and confirms.
    ch(p,
       '    match /parkMenuItems/{itemId} {\n',
       '''    // SHOP_COMMERCE_V1: backend-only orders/payments, owner read access.
    match /souvenirOrders/{orderId} {
      allow get, list: if isAdmin() ||
        (signedIn() && resource.data.ownerUid == request.auth.uid);
      allow create, update, delete: if false;
    }
    match /parkCommercePayments/{paymentId} {
      allow get, list: if isAdmin() ||
        (signedIn() && resource.data.ownerUid == request.auth.uid);
      allow create, update, delete: if false;
    }
    match /parkMenuItems/{itemId} {
''')

    # 6: Photo payment page: use Stripe and only navigate after verified status.
    p='lib/photos/photo_checkout_pages.dart'
    ch(p,"import 'photo_repository.dart';\n",
         "import 'photo_repository.dart';\nimport '../commerce/stripe_commerce_client.dart';\n")
    ch(p,'  String method = \'card\';\n  String? error;\n',
         "  StripeCommerceClient get _commerce => StripeCommerceClient(\n"
       "    auth: widget.repository is FirebasePhotoRepository\n"
       "      ? (widget.repository as FirebasePhotoRepository).auth : null);\n"
       "  String? _pendingCommerceId;\n  String? _pendingPhotoRequestId;\n  String? error;\n  String get _stripePhotoKey => 'photo_stripe_pending_${widget.repository.uid}';\n")
    ch(p,'    refresh();\n  }\n\n  Future<void> refresh() async {',
       "    refresh();\n    _loadStripePending();\n  }\n\n"
       "  Future<void> _loadStripePending() async {\n"
       "    final prefs=await SharedPreferences.getInstance();\n"
       "    final id=prefs.getString(_stripePhotoKey);\n"
       "    if(mounted && id!=null && id.isNotEmpty) setState(()=>_pendingCommerceId=id);\n"
       "  }\n\n"
       "  Future<void> _finishPhoto(String orderId) async {\n"
       "    final prefs=await SharedPreferences.getInstance();\n"
       "    await prefs.remove(_stripePhotoKey);\n"
       "    await widget.repository.cart.clear();\n"
       "    if(!mounted)return;\n"
       "    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>\n"
       "      PhotoPaymentSuccessPage(repository:widget.repository,orderId:orderId)));\n"
       "  }\n\n"
       "  Future<void> _checkStripePhoto() async {\n"
       "    final id=_pendingCommerceId;\n"
       "    if(id==null || busy)return;\n"
       "    setState(() {busy=true;error=null;});\n"
       "    try {\n"
       "      final result=await _commerce.status(id);\n"
       "      if(result['status']=='paid' && result['photoOrderId'] is String) {\n"
       "        await _finishPhoto(result['photoOrderId'] as String);\n"
       "      } else if(mounted) {\n"
       "        setState(() => error=result['status']=='manual_review'\n"
       "          ? 'Payment received. Photo fulfillment needs staff review. Do not pay again.'\n"
       "          : 'Payment not yet confirmed. Complete checkout, then check again.');\n"
       "      }\n"
       "    }catch(e){if(mounted)setState(()=>error=e.toString());}\n"
       "    finally{if(mounted)setState(()=>busy=false);}\n"
       "  }\n\n"
       "  Future<void> refresh() async {")
    old='''    try {
      final result = await confirmPhotoPurchase(widget.repository, {
        ...body,
        'expectedTotalMinor': quote!['totalMinor'],
        'paymentMethod': method,
      });
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PhotoPaymentSuccessPage(
              repository: widget.repository,
              orderId: result['orderId'] as String,
            ),
          ),
        );
      }
    } catch (e) {
'''
    new='''    try {
      final total=(quote!['totalMinor'] as num).toInt();
      if(total==0) {
        // A fully points-funded photo order requires no bank charge.
        final result=await confirmPhotoPurchase(widget.repository, {
          ...body,'expectedTotalMinor':0,'paymentMethod':'points',
        });
        await _finishPhoto(result['orderId'] as String);
      } else {
        final requestId=_pendingPhotoRequestId ?? widget.repository.newRequestId();
        _pendingPhotoRequestId=requestId;
        final response=await _commerce.checkout('photo',requestId,body);
        final id=response['orderId'] as String?;
        if(id!=null){
          _pendingCommerceId=id;
          await (await SharedPreferences.getInstance()).setString(_stripePhotoKey,id);
        }
        if(response['status']=='paid' && response['photoOrderId'] is String) {
          await _finishPhoto(response['photoOrderId'] as String);
        } else if(response['url'] is String) {
          await _commerce.openCheckout(response['url'] as String);
          if(mounted)setState(()=>error='Return here and use Check Payment Status after payment.');
        } else {
          throw StateError('Payment is pending. Use Check Payment Status.');
        }
      }
    } catch (e) {
'''
    ch(p,old,new)
    # Replace misleading payment-method selector: actual methods depend on Stripe checkout.
    start=updated[p].find('              for (final option in [\n',updated[p].find('class _PhotoPaymentPageState'))
    end_marker='''            ],
          ),
        ),
        const SizedBox(height: 20),'''
    end=updated[p].find(end_marker,start)
    if start<0 or end<0:raise RuntimeError('Payment method selector changed; no patch applied.')
    updated[p]=updated[p][:start]+'''              const ListTile(
                leading: Icon(Icons.lock_outline,color:photoRose),
                title: Text('Stripe Secure Checkout'),
                subtitle: Text('Available card, FPX and wallet methods depend on your Stripe account.'),
              ),
'''+updated[p][end:]
    ch(p,
       "        const SizedBox(height: 15),\n        const Row(\n          mainAxisAlignment: MainAxisAlignment.center,\n",
       "        if (_pendingCommerceId != null) ...[\n"
       "          const SizedBox(height: 10),\n"
       "          PhotoButton('Check Payment Status', onPressed:_checkStripePhoto, busy:busy),\n"
       "        ],\n"
       "        const SizedBox(height: 15),\n        const Row(\n          mainAxisAlignment: MainAxisAlignment.center,\n")
    ch(p,
       "          onPressed: !accepted || loading || quote == null ? null : pay,\n",
       "          onPressed: !accepted || loading || quote == null || _pendingCommerceId != null ? null : pay,\n")

    # All anchors verified, now safe backup then write. Camera modifications are not touched.
    backups=ROOT.parent/('BeforeCommercePatch_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    backups.mkdir(parents=True)
    created=[]
    try:
        for name,raw in original.items():
            dest=backups/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
        for name,s in updated.items():
            newline,bom=metadata[name]
            data=s.replace('\n',newline).encode('utf-8')
            if bom:data=b'\xef\xbb\xbf'+data
            paths[name].write_bytes(data)
        for name in additions:
            dest=ROOT/name
            if dest.exists():
                # Checked its SHA-256 before touching ANY project files.
                continue
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(staged[name],dest)
            created.append(dest)
    except Exception:
        for name,raw in original.items():paths[name].write_bytes(raw)
        # Remove only files THIS invocation created, not user files staged earlier.
        for dest in created:dest.unlink(missing_ok=True)
        raise
    print('SUCCESS: Souvenir catalogue/stock + guarded photo & souvenir Stripe checkout source installed.')
    print('Ticket Stripe flow retained. Local Stripe port set to 8788.')
    print('Original files backed up outside repo:',backups)
    print('IMPORTANT: NO Firebase deploy, NO Stripe charge, NO GitHub changes were performed.')
    print('Run flutter analyze + node --check before considering deployment.')

if __name__=='__main__':
    try:main()
    except Exception as e:
        print('PATCH NOT APPLIED:',e,file=sys.stderr)
        sys.exit(1)
