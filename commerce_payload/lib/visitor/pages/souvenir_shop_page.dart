import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../commerce/stripe_commerce_client.dart';

class SouvenirShopPage extends StatefulWidget {
  const SouvenirShopPage({super.key});
  @override
  State<SouvenirShopPage> createState() => _SouvenirShopPageState();
}

class _SouvenirShopPageState extends State<SouvenirShopPage> {
  final _client = StripeCommerceClient();
  final Map<String,int> _cart = {};
  String? _shopId, _pendingPaymentId, _pendingRequestId, _notice;
  bool _busy = false, _orders = false;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _pendingKey => 'souvenir_pending_$_uid';
  String _money(int cents) => 'RM ${(cents/100).toStringAsFixed(2)}';
  String _newId() => List.generate(24, (_) => Random.secure().nextInt(256)
      .toRadixString(16).padLeft(2,'0')).join();

  @override
  void initState() {
    super.initState();
    _loadPending();
  }
  Future<void> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pendingKey);
    if (mounted && saved != null && saved.isNotEmpty) {
      setState(() => _pendingPaymentId = saved);
    }
  }
  Future<void> _checkPayment() async {
    final id = _pendingPaymentId;
    if (id == null || _busy) return;
    setState(() {_busy=true;_notice=null;});
    try {
      final result = await _client.status(id);
      if (!mounted) return;
      final status = result['status'];
      if (status == 'paid') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingKey);
        setState(() {
          _pendingPaymentId=null;_pendingRequestId=null;
          _cart.clear();_orders=true;
          _notice='Payment confirmed. Your souvenir order is ready for staff processing.';
        });
      } else if(status == 'expired') {
        await (await SharedPreferences.getInstance()).remove(_pendingKey);
        setState(() {_pendingPaymentId=null;_pendingRequestId=null;
          _notice='Checkout expired. Stock was released. Try again.';});
      } else {
        setState(() => _notice = status == 'manual_review'
          ? 'Payment needs staff review. Please do not pay again.'
          : 'Payment is not confirmed. Complete Stripe Checkout or check later.');
      }
    } catch(e) {
      if(mounted) setState(() => _notice=e.toString());
    } finally {
      if(mounted) setState(() => _busy=false);
    }
  }
  Future<void> _checkout(List<QueryDocumentSnapshot<Map<String,dynamic>>> products) async {
    if (_busy || _cart.isEmpty || _pendingPaymentId!=null) return;
    final selected = <Map<String,dynamic>>[];
    for (final p in products) {
      final count = _cart[p.id] ?? 0;
      if (count > 0) selected.add({'id':p.id,'quantity':count});
    }
    if (selected.isEmpty) return;
    setState(() {_busy=true;_notice=null;});
    try {
      final quote = await _client.shopQuote(selected);
      final agreed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title: const Text('Confirm Souvenir Order'),
        content: Text('Total: ${_money((quote['totalMinor'] as num).toInt())}\n'
          'Payment will open Stripe secure checkout.\n'
          'Stock is reserved during checkout.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Pay Now'))],
      ));
      if (agreed != true || !mounted) return;
      final requestId = _pendingRequestId ?? _newId();
      _pendingRequestId = requestId;
      final response = await _client.checkout('souvenir',requestId,{'items':selected});
      if (!mounted) return;
      _pendingPaymentId=response['orderId'] as String?;
      final id=_pendingPaymentId;
      if(id!=null) await (await SharedPreferences.getInstance()).setString(_pendingKey,id);
      if (response['status'] == 'paid') {
        await _checkPayment();
      } else if (response['url'] is String) {
        await _client.openCheckout(response['url'] as String);
        if (mounted) setState(() => _notice='Return here and tap Check Payment Status after paying.');
      } else {
        throw StateError('No checkout URL. Please check payment status.');
      }
    } catch(e) {
      if(mounted) setState(() => _notice=e.toString());
    } finally {
      if(mounted) setState(()=>_busy=false);
    }
  }

  Widget _orderHistory() {
    if (_uid.isEmpty) return const Center(child:Text('Sign in to see your orders.'));
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection('souvenirOrders')
        .where('ownerUid',isEqualTo:_uid).snapshots(),
      builder:(context,s) {
        if(s.hasError)return const Text('Orders cannot be loaded. Check Firestore permissions.');
        if(!s.hasData)return const Center(child:CircularProgressIndicator());
        final orders=[...s.data!.docs]..sort((a,b){
          final at=a.data()['createdAt'] as Timestamp?;
          final bt=b.data()['createdAt'] as Timestamp?;
          return (bt?.millisecondsSinceEpoch??0).compareTo(at?.millisecondsSinceEpoch??0);
        });
        if(orders.isEmpty)return const Center(child:Text('No souvenir purchases yet.'));
        return ListView(children:[for(final order in orders)
          Card(child:ListTile(
            title:Text('Order ${order.id.substring(0,10).toUpperCase()}'),
            subtitle:Text((order.data()['items'] as List? ?? [])
              .map((e)=>'${e['name']} ×${e['quantity']}').join(' · ')),
            trailing:Column(mainAxisSize:MainAxisSize.min,
              children:[Text(_money((order.data()['totalMinor'] as num?)?.toInt()??0)),
                Text((order.data()['fulfillmentStatus']??'Paid').toString())]),
          ))]);
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor:const Color(0xFFFDF4EF),
    appBar:AppBar(title:const Text('Souvenir Shop'),actions:[
      IconButton(tooltip:_orders?'Shop':'My Orders',
        onPressed:()=>setState(()=>_orders=!_orders),
        icon:Icon(_orders?Icons.storefront:Icons.receipt_long)),
    ]),
    body:Column(children:[
      if (_pendingPaymentId!=null) MaterialBanner(
        content:const Text('You have an unfinished payment.'),
        actions:[TextButton(onPressed:_busy?null:_checkPayment,
          child:const Text('Check Payment Status'))]),
      if(_notice!=null) Padding(padding:const EdgeInsets.all(12),
        child:Text(_notice!,style:const TextStyle(color:Color(0xFF8A5F60)))),
      if(_busy)const LinearProgressIndicator(),
      Expanded(child:_orders?_orderHistory():_catalogue()),
    ]),
  );

  Widget _catalogue() => StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:FirebaseFirestore.instance.collection('attractions').snapshots(),
    builder:(ctx,shopsSnapshot) {
      if(shopsSnapshot.hasError)return const Center(child:Text('Unable to load park shops.'));
      if(!shopsSnapshot.hasData)return const Center(child:CircularProgressIndicator());
      final shops=shopsSnapshot.data!.docs.where((d){
        final p=d.data(),kind=(p['kind']??p['category']??'').toString().toLowerCase();
        return p['deletedAt']==null && (kind.contains('shop')||kind.contains('retail')||
          kind.contains('souvenir')||kind.contains('shopping')||kind.contains('gift'));
      }).toList();
      final ids=shops.map((d)=>d.id).toSet();
      final chosen=ids.contains(_shopId)?_shopId:(shops.isEmpty?null:shops.first.id);
      return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream:FirebaseFirestore.instance.collection('parkMenuItems')
          .where('active',isEqualTo:true).snapshots(),
        builder:(ctx,itemsSnapshot){
          if(itemsSnapshot.hasError)return const Center(child:Text('Product catalogue unavailable. Check Firestore rules.'));
          if(!itemsSnapshot.hasData)return const Center(child:CircularProgressIndicator());
          final all=itemsSnapshot.data!.docs.where((d)=>ids.contains(d.data()['storeId'])).toList();
          final entries=all.where((d)=>d.data()['storeId']==chosen).toList();
          final selected=all.where((d)=>_cart.containsKey(d.id)).toList();
          final total=selected.fold<int>(0,(n,d)=>n+((_cart[d.id]??0)*
            ((d.data()['priceMinor'] as num?)?.toInt()??0)));
          return Column(children:[
            if(shops.isNotEmpty) Padding(padding:const EdgeInsets.all(12),
              child:DropdownButtonFormField<String>(
                initialValue:chosen,decoration:const InputDecoration(labelText:'Shop'),
                items:[for(final s in shops) DropdownMenuItem(value:s.id,
                  child:Text(s.data()['name']?.toString()??'Souvenir Shop'))],
                onChanged:(v)=>setState(()=>_shopId=v),
              )),
            Expanded(child:entries.isEmpty?const Center(child:Text('No souvenirs are available here yet.')):
              ListView.builder(itemCount:entries.length,itemBuilder:(context,index){
                final d=entries[index],p=d.data(),stock=(p['stockQuantity'] as num?)?.toInt()??0;
                final qty=_cart[d.id]??0,price=(p['priceMinor'] as num?)?.toInt()??0;
                return Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:5),
                  child:Padding(padding:const EdgeInsets.all(10),child:Row(children:[
                    SizedBox(width:75,height:75,child:p['imageUrl'] is String &&
                      (p['imageUrl'] as String).startsWith('https://')
                      ?Image.network(p['imageUrl'],fit:BoxFit.cover,
                        errorBuilder:(_,__,___)=>const Icon(Icons.image_not_supported))
                      :const Icon(Icons.shopping_bag_outlined)),
                    const SizedBox(width:12),
                    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(p['name']?.toString()??'Souvenir',style:const TextStyle(fontWeight:FontWeight.bold)),
                      Text(p['description']?.toString()??'',maxLines:2,overflow:TextOverflow.ellipsis),
                      Text('${_money(price)} · ${stock>0?'$stock left':'Out of stock'}'),
                    ])),
                    Column(children:[
                      IconButton(onPressed:qty<=0||_pendingPaymentId!=null?null:
                        ()=>setState((){if(qty==1){_cart.remove(d.id);}else{_cart[d.id]=qty-1;}}),
                        icon:const Icon(Icons.remove_circle_outline)),
                      Text('$qty'),
                      IconButton(onPressed:stock<=qty||_pendingPaymentId!=null?null:
                        ()=>setState(()=>_cart[d.id]=qty+1),
                        icon:const Icon(Icons.add_circle_outline)),
                    ]),
                  ])));
              })),
            if(_cart.isNotEmpty)SafeArea(child:Padding(padding:const EdgeInsets.all(12),
              child:SizedBox(width:double.infinity,child:FilledButton.icon(
                onPressed:_busy||_pendingPaymentId!=null?null:()=>_checkout(all),
                icon:const Icon(Icons.payment),
                label:Text('Checkout · ${_money(total)}'),
              )))),
          ]);
        });
    });
}
