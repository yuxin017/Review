import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'souvenir_shop_page.dart'; // PARKSMART_V16_REFUND_CROWD_HISTORY
import 'package:flutter/material.dart';
import '../../photos/photo_repository.dart';
import '../../photos/photo_order_pages.dart';
import '../../photos/photo_widgets.dart';
import '../models/tickets.dart';
import '../services/ticket_repository.dart';
import '../services/ticket_receipt.dart';
import '../visitor_main_page.dart';

class CombinedPurchaseHistoryPage extends StatefulWidget {
  const CombinedPurchaseHistoryPage({super.key});
  @override
  State<CombinedPurchaseHistoryPage> createState() =>
      _CombinedPurchaseHistoryPageState();
}

class _CombinedPurchaseHistoryPageState
    extends State<CombinedPurchaseHistoryPage> {
  late final tickets = FirebaseTicketRepository().orders(),
      photos = FirebasePhotoRepository();
  @override
  Widget build(BuildContext context) => PhotoFrame(
    title: 'Purchase History',
    helpTitle: 'Your purchases',
    helpText:
        'Use the filters to find ticket and photo orders. Open a ticket purchase for its passes and receipt, or open a photo order for digital downloads and print collection. Orders remain linked to the account used for the purchase.',
    body: StreamBuilder<List<TicketOrder>>(
      stream: tickets,
      builder: (context, s) {
        if (s.hasError) {
          return const Center(
            child: Text('Unable to load your orders. Please try again.'),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return PurchaseHistoryBody(
          orders: s.data!,
          photos: photos,
          onTickets: (order) {
            Navigator.of(context).popUntil((r) => r.isFirst);
            VisitorMainPage.openTicketOrder(context, order.id);
          },
        );
      },
    ),
  );
}

// PARKSMART_V16_REFUND_CROWD_HISTORY: three live order channels, one history.
class PurchaseHistoryBody extends StatefulWidget {
  final List<TicketOrder> orders;
  final PhotoRepository? photos;
  final ValueChanged<TicketOrder> onTickets;
  const PurchaseHistoryBody({super.key,required this.orders,required this.onTickets,this.photos});
  @override
  State<PurchaseHistoryBody> createState()=>_PurchaseHistoryBodyState();
}
class _PurchaseHistoryBodyState extends State<PurchaseHistoryBody> {
  late final photoOrders=widget.photos?.orders() ?? Stream<List<ParkPhoto>>.value([]);
  late final souvenirOrders=FirebaseFirestore.instance.collection('souvenirOrders')
    .where('ownerUid',isEqualTo:FirebaseAuth.instance.currentUser?.uid ?? '').snapshots();
  String filter='All',query='';
  @override
  Widget build(BuildContext context)=>StreamBuilder<List<ParkPhoto>>(
    stream:photoOrders,
    builder:(context,photos)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:souvenirOrders,
      builder:(context,souvenirs){
        final rows=<({DateTime? time,TicketOrder? ticket,ParkPhoto? photo,QueryDocumentSnapshot<Map<String,dynamic>>? souvenir})>[
          if(filter=='All'||filter=='Tickets')
            for(final t in widget.orders) (time:t.createdAt,ticket:t,photo:null,souvenir:null),
          if(filter=='All'||filter=='Photos')
            for(final p in photos.data??<ParkPhoto>[])
              (time:(p.data['createdAt'] as Timestamp?)?.toDate(),ticket:null,photo:p,souvenir:null),
          if(filter=='All'||filter=='Souvenirs')
            for(final d in souvenirs.data?.docs??<QueryDocumentSnapshot<Map<String,dynamic>>>[])
              if(['paid','refunded'].contains(d.data()['status']))
                (time:(d.data()['paidAt'] as Timestamp?)?.toDate(),ticket:null,photo:null,souvenir:d),
        ]..sort((a,b)=>(b.time??DateTime(1970)).compareTo(a.time??DateTime(1970)));
        final matched=rows.where((r){
          final name=r.ticket?.packageName ?? (r.photo!=null
            ? (r.photo!.data['items'] as List? ?? []).map((x)=>x['title']).join(' ')
            : (r.souvenir!.data()['items'] as List? ?? []).map((x)=>x['name']).join(' '));
          final reference=r.ticket?.reference ?? (r.photo!=null
            ? photoOrderReference(r.photo!.id) : r.souvenir!.id);
          return '$name $reference'.toLowerCase().contains(query.toLowerCase());
        }).toList();
        return ListView(padding:const EdgeInsets.all(20),children:[
          Wrap(spacing:7,runSpacing:7,children:[
            for(final value in ['All','Tickets','Photos','Souvenirs'])
              ChoiceChip(label:Text(value),selected:filter==value,
                onSelected:(_)=>setState(()=>filter=value)),
          ]),
          const SizedBox(height:18),
          TextField(onChanged:(v)=>setState(()=>query=v),
            decoration:const InputDecoration(hintText:'Search purchase or order number',
              prefixIcon:Icon(Icons.search),border:OutlineInputBorder(),isDense:true)),
          const SizedBox(height:21),
          if(photos.hasError) const PhotoPanel(child:Text('Photo orders cannot be loaded.')),
          if(souvenirs.hasError) const PhotoPanel(child:Text('Souvenir orders cannot be loaded. Check Firestore permissions.')),
          if(matched.isEmpty && !photos.hasError && !souvenirs.hasError)
            const PhotoPanel(child:Padding(padding:EdgeInsets.all(24),
              child:Text('No confirmed purchases found.'))),
          for(final row in matched)
            Padding(padding:const EdgeInsets.only(bottom:12),child:PhotoPanel(
              child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                Row(children: [
                  Expanded(child: Text(row.ticket != null ? 'Park Tickets' : row.photo != null ? 'Smart Photos' : 'Park Shop',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(row.souvenir?.data()['status'] == 'refunded' || row.ticket?.status == 'refunded'
                      ? 'Refunded'
                      : row.souvenir?.data()['refundStatus'] == 'requested'
                          ? 'Refund requested'
                          : row.ticket != null && row.ticket!.status != 'completed'
                              ? 'Order details'
                              : 'Confirmed',
                    style: const TextStyle(color: photoRose, fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
                const Divider(height: 20),
                Row(children:[
                  CircleAvatar(backgroundColor:const Color(0xFFF3E3DE),
                    child:Icon(row.ticket!=null?Icons.confirmation_number_outlined:
                      row.photo!=null?Icons.photo_library_outlined:Icons.shopping_bag_outlined,
                      color:photoRose)),
                  const SizedBox(width:12),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(row.ticket?.packageName ?? (row.photo!=null?'Park Photo Purchase':'Souvenir Purchase'),
                      style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)),
                    const SizedBox(height:4),
                    Text(row.ticket?.reference ?? (row.photo!=null
                      ? photoOrderReference(row.photo!.id)
                      : '#${row.souvenir!.id.split('').take(10).join().toUpperCase()}'),
                      style:const TextStyle(fontSize:11,color:Color(0xFF7C8289))),
                    if(row.time!=null) Text('${row.time!.toLocal().day}/${row.time!.toLocal().month}/${row.time!.toLocal().year}',
                      style:const TextStyle(fontSize:11,color:Color(0xFF7C8289))),
                  ])),
                  Text(row.ticket?.paymentLabel ?? photoMoney(row.photo!=null
                    ? (row.photo!.data['totalMinor'] as num? ?? 0)
                    : (row.souvenir!.data()['totalMinor'] as num? ?? 0)),
                    style:const TextStyle(fontSize:15,fontWeight:FontWeight.w700)),
                ]),
                const Divider(height:24),
                Text(row.ticket!=null
                  ? '${row.ticket!.quantity} tickets · ${displayParkDate(row.ticket!.visitDate)}'
                  : row.photo!=null
                    ? '${(row.photo!.data['items'] as List? ?? []).length} photos · Confirmed'
                    : '${(row.souvenir!.data()['items'] as List? ?? []).length} item types · ${row.souvenir!.data()['status']=='refunded'?'Refunded':(row.souvenir!.data()['refundStatus']=='requested'?'Refund requested':'Paid')}',
                  style:const TextStyle(fontSize:12,color:photoRose)),
                const SizedBox(height:12),
                if(row.ticket!=null)
                  Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                    OutlinedButton(onPressed:()=>downloadTicketReceipt(context,row.ticket!),
                      child:const Text('Receipt')),
                    FilledButton(onPressed:()=>widget.onTickets(row.ticket!),
                      child:const Text('View Tickets')),
                  ])
                else if(row.photo!=null)
                  PhotoButton('View Photo Order',outlined:true,onPressed:()=>Navigator.push(
                    context,MaterialPageRoute(builder:(_)=>PhotoOrderDetailPage(
                      repository:widget.photos!,orderId:row.photo!.id))))
                else
                  PhotoButton('View Souvenir Order',outlined:true,onPressed:()=>Navigator.push(
                    context,MaterialPageRoute(builder:(_)=>const SouvenirShopPage(initialOrders:true)))),
              ]),
            )),
        ]);
      },
    ),
  );
}
