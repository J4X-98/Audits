import pandas as pd

# Read the CSV file
df = pd.read_csv('./mint_whitelist.csv')

# Filter rows with method "Mint Whitelist"
filtered_df = df[df['Method'] == 'Mint Whitelist']

# Group by 'From' address and calculate the sum of 'Value_IN(ETH)'
grouped_df = filtered_df.groupby('From')['Value_IN(ETH)'].sum()

# Sort the grouped data by the total value in descending order
sorted_df = grouped_df.sort_values(ascending=False)

# Create a DataFrame for the results
result_df = pd.DataFrame({'From Address': sorted_df.index, 'Total Value': sorted_df.values})

# Write the results to a CSV file
result_df.to_csv('result.csv', index=False)
