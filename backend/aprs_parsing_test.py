import aprslib

packet = aprslib.parse("K8SDR-10>APRS,TCPIP*::AD8NT    :from K8SDR: Hi there")

print(packet)

