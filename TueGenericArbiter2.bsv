package TueGenericArbiter2;

export TueGenericArbiter2(..);
export mkTueGenericArbiter2;
//export tueCounter;

import Bluetree2::*;
import BluetreeCommit::*;
import GetPut::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;

typedef UInt#(8) TueCounter; // Change this later...

interface TueGenericArbiter2#(type client_pkt, type server_pkt);
    interface Client#(client_pkt, server_pkt) client;
    interface Server#(client_pkt, server_pkt) server;
endinterface

module mkTueGenericArbiter2#(tueCounter inCr,
                             tueCounter cuCr,
                             tueCounter rCr,
                             tueCounter numerator,
                             tueCounter denominator,
                             tueCounter prio,
                             tueCounter prio_off,
                             tueCounter upper_bound,
                             tueCounter lower_bound,
                             tueCounter si_counter,
                             tueCounter ri_counter) (TueGenericArbiter2#(client_pkt, server_pkt))
    provisos(BluetreePriorityOrdering#(client_pkt, client_prio), // Client packets have a priority
             BluetreeServerType#(server_pkt),                    // Server packets have a message type
             Bits#(client_prio, client_prio_bits),               // The size of client_prio is known
             Bits#(client_pkt, client_pkt_bits),                 // Sizes of server/client packets are known
             Bits#(server_pkt, server_pkt_bits),
             Add#(_a_, client_prio_bits, 8),                     // Size of client priority is small enough to fit here
             Alias#(TueCounter, tueCounter));                    // Artefact from bugs...
    FIFOF#(client_pkt) issue_queue <- mkFIFOF();
    FIFOF#(server_pkt) response_queue <- mkFIFOF();

    Reg#(tueCounter) si_countdown <- mkReg(si_counter - 1); // Scheduling interval
    Reg#(tueCounter) ri_countdown <- mkReg(ri_counter - 1); // Replenishment interval counter
    Reg#(tueCounter) cur_credit   <- mkReg(inCr);

    PulseWire pkt_accepted <- mkPulseWire();
    PulseWire is_backlogged <- mkPulseWire();
    
    Reg#(Bool) startup <- mkReg(True);
    Reg#(Bool) wc_issue <- mkReg(False);
    RWire#(client_pkt) issue_pkt <- mkRWire();
    
    // This relies on a hack. Since ri_countdown only ticks when ri_countdown == 0, and ri_counter == 0
    // disables the RI mechanism, ri_counter-1 will *not* ever be zero if the ri mechanism is disabled, hence
    // be fine. Ish.
    rule updateRI(ri_counter != 0 && si_countdown == 0);
        if(ri_countdown == 0)
            ri_countdown <= ri_counter - 1;
        else
            ri_countdown <= ri_countdown - 1;
    endrule

    rule setBacklogged;
        if(issue_queue.notEmpty())
            is_backlogged.send();
    endrule
    
    rule printConfig(startup);
    	$display("===================");
    	$display("Arbiter Config:");
    	$display("inCr: %d", inCr);
    	$display("cuCr: %d", cuCr);
    	$display("rCr: %d", rCr);
    	$display("numerator: %d", numerator);
    	$display("denominator: %d", denominator);
    	$display("priority: %d", prio);
    	$display("W/C priority: %d", prio_off);
    	$display("upper bound: %d", upper_bound);
    	$display("lower bound: %d", lower_bound);
    	$display("si_counter: %d", si_counter);
    	$display("ri_counter: %d", ri_counter);
    	$display("==================");
    	
    	startup <= False;
    endrule

    // Calc. service intervals.
    rule updateSI;
        if(si_countdown == 0)
            si_countdown <= si_counter - 1; // Refresh.
        else
            si_countdown <= si_countdown - 1;
    endrule

    // Need to do the accounting on each dispatch tick.
    // We currently make the assumption that a "accepted" message cannot arrive in the same
    // cycle as si_countdown being 0.
    // This needs making more complex for the CCSP case. In future...
    (* mutually_exclusive="accounting,handlePktDone" *)
    rule accounting(si_countdown == 0);
        if(ri_countdown != 0) begin
            if(inCr > 0 && cur_credit + numerator > inCr && !is_backlogged) // If there's an initial credit, it's as high as cur_credit can go.
                cur_credit <= inCr;
            else
                cur_credit <= cur_credit + numerator;
        end
    endrule
    
    (* mutually_exclusive="handlePktDone,doIssue" *)
    rule handlePktDone(pkt_accepted);
    	if(wc_issue == False) begin
            if(cur_credit < denominator)
    		  cur_credit <= 0;
            else    
    		  cur_credit <= cur_credit - denominator;
    	end
    	    
        issue_queue.deq();
    endrule
        
    rule doIssue(si_countdown == 0 && 
    		 (prio_off != 0 || 
    		  (cur_credit >= lower_bound && cur_credit <= upper_bound)));
    	// Are we dispatching work-conserving?
    	client_pkt pkt = issue_queue.first();
    	client_prio pkt_priority;
    	if(cur_credit >= lower_bound && cur_credit <= upper_bound) begin
    	    pkt_priority = unpack(truncate(pack(prio)));        // Dat type conversion...
    	    wc_issue <= False;
    	    //$display("ARB%d Got service, dispatching @ %d", prio, $time);
    	end
        else begin
    	    wc_issue <= True;
    	    pkt_priority = unpack(truncate(pack(prio_off)));
    	end

        pkt = setCpuPrio(pkt, pkt_priority);
    	
    	issue_pkt.wset(pkt);
    endrule

    
    // Only need this bit if RI is enabled...
    // Because of races, we need to reset the credits *after* the last packet in an interval 
    // has been dispatched, and potentially accepted and accounted for.
    if(ri_counter != 0) begin
        rule riReplenish(!pkt_accepted && si_countdown == 1 && ri_countdown == ri_counter - 1);
            cur_credit <= rCr;
        endrule
    end
    
    interface Client client;
        interface Get request;
            // Can only dispatch once per service interval.
            // Also check we can either do work conservation, or that we have enough credit.
	    method ActionValue#(client_pkt) get() if(issue_pkt.wget matches tagged Valid .pkt); 
		return pkt;
            endmethod
        endinterface

        interface Put response;
            method Action put(server_pkt pkt);
                if(getMessageType(pkt) == BT_MEM_SCHEDULED)
                    pkt_accepted.send();
                else
                    response_queue.enq(pkt);
            endmethod
        endinterface
    endinterface

    interface Server server;
        interface Put request;
            method Action put(client_pkt pkt);
                issue_queue.enq(pkt);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(server_pkt) get();
                response_queue.deq();
                return response_queue.first();
            endmethod
        endinterface
    endinterface
endmodule

endpackage