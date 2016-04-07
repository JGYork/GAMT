package BluetreeRateLimiterRoot2;

export BluetreeRateLimiterRoot2(..);
export mkBluetreeRateLimiterRoot2;

import Bluetree2::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;
import FIFOF::*;

interface BluetreeRateLimiterRoot2#(type client_pkt, type server_pkt);
    interface Server#(client_pkt, server_pkt) server;
    interface Client#(client_pkt, server_pkt) client;
endinterface

module mkBluetreeRateLimiterRoot2(BluetreeRateLimiterRoot2#(client_pkt, server_pkt))
    provisos(BluetreeRoutable#(client_pkt, cpu_id_type), // We need to tie the CPU ID bits to the same type
             BluetreeRoutable#(server_pkt, cpu_id_type),
             Bits#(client_pkt, client_pkt_bits),
             Bits#(server_pkt, server_pkt_bits),
             Bits#(cpu_id_type, cpu_id_bits),
             BluetreeClientType#(client_pkt),
             BluetreeServerType#(server_pkt)
    );
    FIFOF#(client_pkt) relayUp <- mkFIFOF();
    // Because of Bluespec's rules, we need unguarded dequeue on these FIFOs...
    FIFOF#(server_pkt) relayDown <- mkGFIFOF(False, True);
    FIFOF#(server_pkt) relayScheduledDown <- mkGFIFOF(False, True);

    interface Client client;
        interface Get request = toGet(relayUp);
        interface Put response = toPut(relayDown);
    endinterface

    interface Server server;
        interface Put request;
            method Action put(client_pkt pkt);
                // If a packet got here, it's scheduled, so reply with the scheduled message
                server_pkt spkt = unpack(0);
                spkt = setMessageType(spkt, BT_MEM_SCHEDULED);
                spkt = setCpuId(spkt, getCpuId(pkt));

                if(getClientMessageType(pkt) == BT_PREFETCH_HIT)
                    pkt = setClientMessageType(pkt, BT_PREFETCH);

                relayUp.enq(pkt);
                relayScheduledDown.enq(spkt);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(server_pkt) get() if(relayScheduledDown.notEmpty() || relayDown.notEmpty());
                if(relayScheduledDown.notEmpty()) begin
//                    $display("CCSPRateRoot: Relaying scheduled message down to CPU %d", getCpuId(relayScheduledDown.first()));
                    relayScheduledDown.deq();
                    return relayScheduledDown.first();
                end
                else begin
//                    $display("CCSPRateRoot: Relaying data to CPU %d", getCpuId(relayDown.first()));
                    relayDown.deq();
                    return relayDown.first();
                end
            endmethod
        endinterface
    endinterface
endmodule

endpackage